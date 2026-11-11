use std::io::{Read, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream, ToSocketAddrs, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use crate::config::ProxyConfig;

const READ_TIMEOUT: Duration = Duration::from_millis(500);
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);

pub fn encode_userinfo(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z'
            | b'a'..=b'z'
            | b'0'..=b'9'
            | b'-'
            | b'.'
            | b'_'
            | b'~'
            | b'!'
            | b'$'
            | b'&'
            | b'\''
            | b'('
            | b')'
            | b'*'
            | b'+'
            | b','
            | b';'
            | b'=' => encoded.push(byte as char),
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

pub fn proxy_url(proxy: &ProxyConfig) -> Option<String> {
    if proxy.host.is_empty() || proxy.port == 0 {
        return None;
    }
    let mut url = String::from("socks5h://");
    let user = proxy.username.trim();
    if !user.is_empty() {
        url.push_str(&encode_userinfo(user));
        url.push(':');
        url.push_str(&encode_userinfo(proxy.password.trim()));
        url.push('@');
    }
    url.push_str(&proxy.host);
    url.push(':');
    url.push_str(&proxy.port.to_string());
    Some(url)
}

pub fn parse_udp_address(address: &str) -> Option<(String, u16)> {
    let rest = address.strip_prefix("udp://")?;
    let authority = rest.split(['/', '?']).next()?;
    if authority.contains(':') {
        let (host, port) = authority.rsplit_once(':')?;
        let port: u16 = port.parse().ok()?;
        Some((host.trim_matches(['[', ']']).to_string(), port))
    } else if authority.is_empty() {
        None
    } else {
        Some((authority.to_string(), 1212))
    }
}

fn resolve(host: &str, port: u16) -> Result<SocketAddr, String> {
    let mut candidates: Vec<SocketAddr> = (host, port)
        .to_socket_addrs()
        .map_err(|error| format!("не удалось определить адрес {host}: {error}"))?
        .collect();
    candidates.sort_by_key(|addr| !addr.is_ipv4());
    candidates
        .into_iter()
        .next()
        .ok_or_else(|| format!("адрес {host} не найден"))
}

fn connect_tcp(endpoint: SocketAddr) -> Result<TcpStream, String> {
    let stream = TcpStream::connect_timeout(&endpoint, Duration::from_secs(10))
        .map_err(|error| format!("не удалось подключиться к {endpoint}: {error}"))?;
    stream.set_nodelay(true).ok();
    Ok(stream)
}

fn connect_prefer_ipv4(host: &str, port: u16) -> Result<TcpStream, String> {
    if let Ok(address) = host.parse::<IpAddr>() {
        return connect_tcp(SocketAddr::new(address, port));
    }
    let mut last = format!("{host}:{port} недоступен");
    for candidate in (host, port)
        .to_socket_addrs()
        .map_err(|error| error.to_string())?
    {
        match connect_tcp(candidate) {
            Ok(stream) => return Ok(stream),
            Err(error) => last = error,
        }
    }
    Err(last)
}

fn read_exact(stream: &mut TcpStream, buffer: &mut [u8]) -> Result<(), String> {
    let mut filled = 0;
    while filled < buffer.len() {
        let read = stream
            .read(&mut buffer[filled..])
            .map_err(|error| format!("обрыв соединения с прокси: {error}"))?;
        if read == 0 {
            return Err("прокси закрыл управляющее соединение".into());
        }
        filled += read;
    }
    Ok(())
}

fn handshake(stream: &mut TcpStream, proxy: &ProxyConfig) -> Result<(), String> {
    let user = proxy.username.trim();
    let methods: Vec<u8> = if user.is_empty() {
        vec![1, 0x00]
    } else {
        vec![2, 0x00, 0x02]
    };
    let mut greeting = Vec::with_capacity(methods.len() + 1);
    greeting.push(0x05);
    greeting.extend_from_slice(&methods);
    stream
        .write_all(&greeting)
        .map_err(|error| format!("не удалось отправить приветствие: {error}"))?;
    let mut response = [0u8; 2];
    read_exact(stream, &mut response)?;
    if response[0] != 0x05 {
        return Err("прокси ответил неверной версией протокола".into());
    }
    match response[1] {
        0x00 => Ok(()),
        0x02 => {
            if user.is_empty() {
                return Err("прокси требует логин и пароль".into());
            }
            let user_bytes = user.as_bytes();
            let pass_bytes = proxy.password.trim().as_bytes();
            if user_bytes.len() > 255 || pass_bytes.len() > 255 {
                return Err("логин или пароль слишком длинные".into());
            }
            let mut auth = Vec::with_capacity(user_bytes.len() + pass_bytes.len() + 3);
            auth.push(0x01);
            auth.push(user_bytes.len() as u8);
            auth.extend_from_slice(user_bytes);
            auth.push(pass_bytes.len() as u8);
            auth.extend_from_slice(pass_bytes);
            stream
                .write_all(&auth)
                .map_err(|error| format!("не удалось отправить авторизацию: {error}"))?;
            let mut verdict = [0u8; 2];
            read_exact(stream, &mut verdict)?;
            if verdict[1] != 0x00 {
                return Err("прокси отклонил логин и пароль".into());
            }
            Ok(())
        }
        0xFF => Err("прокси отклонил все способы авторизации".into()),
        other => Err(format!(
            "прокси выбрал неизвестный способ авторизации 0x{other:02X}"
        )),
    }
}

fn encode_address(address: SocketAddr, buffer: &mut Vec<u8>) {
    match address.ip() {
        IpAddr::V4(ip) => {
            buffer.push(0x01);
            buffer.extend_from_slice(&ip.octets());
        }
        IpAddr::V6(ip) => {
            buffer.push(0x04);
            buffer.extend_from_slice(&ip.octets());
        }
    }
    buffer.push((address.port() >> 8) as u8);
    buffer.push((address.port() & 0xFF) as u8);
}

fn udp_associate(
    stream: &mut TcpStream,
    proxy: &ProxyConfig,
    client: SocketAddr,
) -> Result<SocketAddr, String> {
    let bind = if client.ip().is_loopback() {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), client.port())
    } else {
        client
    };
    let mut request = vec![0x05, 0x03, 0x00];
    encode_address(bind, &mut request);
    stream
        .write_all(&request)
        .map_err(|error| format!("не удалось отправить запрос UDP: {error}"))?;
    let mut head = [0u8; 4];
    read_exact(stream, &mut head)?;
    if head[0] != 0x05 {
        return Err("прокси ответил неверной версией протокола".into());
    }
    if head[1] != 0x00 {
        return Err(format!("прокси отклонил UDP: код 0x{:02X}", head[1]));
    }
    let mut address_bytes = match head[3] {
        0x01 => vec![0u8; 4],
        0x04 => vec![0u8; 16],
        0x03 => {
            let mut length = [0u8; 1];
            read_exact(stream, &mut length)?;
            vec![0u8; length[0] as usize]
        }
        other => {
            return Err(format!(
                "прокси вернул неизвестный тип адреса 0x{other:02X}"
            ))
        }
    };
    read_exact(stream, &mut address_bytes)?;
    let mut port_bytes = [0u8; 2];
    read_exact(stream, &mut port_bytes)?;
    let port = ((port_bytes[0] as u16) << 8) | port_bytes[1] as u16;
    let relay_ip = match head[3] {
        0x01 => IpAddr::V4(Ipv4Addr::new(
            address_bytes[0],
            address_bytes[1],
            address_bytes[2],
            address_bytes[3],
        )),
        0x04 => {
            let mut octets = [0u8; 16];
            octets.copy_from_slice(&address_bytes);
            IpAddr::V6(octets.into())
        }
        _ => {
            let host = String::from_utf8_lossy(&address_bytes).to_string();
            resolve(&host, port)?.ip()
        }
    };
    Ok(normalize_relay(SocketAddr::new(relay_ip, port), proxy))
}

fn normalize_relay(relay: SocketAddr, proxy: &ProxyConfig) -> SocketAddr {
    let unspecified = match relay.ip() {
        IpAddr::V4(ip) => ip.is_unspecified(),
        IpAddr::V6(ip) => ip.is_unspecified(),
    };
    let proxy_endpoint = resolve(&proxy.host, proxy.port).ok();
    if unspecified || !is_global_reachable(relay.ip()) {
        if let Some(proxy_addr) = proxy_endpoint {
            return SocketAddr::new(proxy_addr.ip(), relay.port());
        }
    }
    relay
}

fn is_global_reachable(address: IpAddr) -> bool {
    match address {
        IpAddr::V4(ip) => {
            !(ip.is_loopback()
                || ip.is_private()
                || ip.is_link_local()
                || ip.is_unspecified()
                || ip.octets()[0] == 10
                || (ip.octets()[0] == 172 && (16..=31).contains(&ip.octets()[1]))
                || (ip.octets()[0] == 192 && ip.octets()[1] == 168))
        }
        IpAddr::V6(ip) => {
            let octets = ip.octets();
            !(ip.is_loopback()
                || ip.is_unspecified()
                || (octets[0] == 0xFE && (octets[1] & 0xC0) == 0x80))
        }
    }
}

pub fn probe_tcp(proxy: &ProxyConfig) -> Result<u64, String> {
    let started = Instant::now();
    let mut stream = connect_prefer_ipv4(&proxy.host, proxy.port)?;
    stream
        .set_read_timeout(Some(HANDSHAKE_TIMEOUT))
        .map_err(|error| error.to_string())?;
    handshake(&mut stream, proxy)?;
    Ok(started.elapsed().as_millis().max(1) as u64)
}

pub fn probe_udp(proxy: &ProxyConfig) -> Result<(), String> {
    let mut stream = connect_prefer_ipv4(&proxy.host, proxy.port)?;
    stream
        .set_read_timeout(Some(HANDSHAKE_TIMEOUT))
        .map_err(|error| error.to_string())?;
    handshake(&mut stream, proxy)?;
    let local = stream.local_addr().map_err(|error| error.to_string())?;
    let bind_ip = if local.ip().is_loopback() {
        IpAddr::V4(Ipv4Addr::UNSPECIFIED)
    } else {
        local.ip()
    };
    let relay_socket = UdpSocket::bind(SocketAddr::new(bind_ip, 0))
        .map_err(|error| format!("не удалось открыть UDP-сокет: {error}"))?;
    let client = relay_socket
        .local_addr()
        .map_err(|error| error.to_string())?;
    udp_associate(&mut stream, proxy, client)?;
    Ok(())
}

pub fn frame_udp(target: SocketAddr, payload: &[u8]) -> Vec<u8> {
    let mut packet = vec![0u8, 0, 0];
    encode_address(target, &mut packet);
    packet.extend_from_slice(payload);
    packet
}

pub fn parse_udp(packet: &[u8]) -> Option<&[u8]> {
    if packet.len() < 4 || packet[2] != 0x00 {
        return None;
    }
    let mut offset = 4;
    match packet[3] {
        0x01 => offset += 4,
        0x04 => offset += 16,
        0x03 => {
            let length = *packet.get(offset)? as usize;
            offset += 1 + length;
        }
        _ => return None,
    }
    let end = offset.checked_add(2)?;
    if packet.len() < end {
        return None;
    }
    Some(&packet[end..])
}

fn same_address(left: SocketAddr, right: SocketAddr) -> bool {
    if left.port() != right.port() {
        return false;
    }
    match (left.ip(), right.ip()) {
        (IpAddr::V4(a), IpAddr::V4(b)) => a == b,
        (IpAddr::V6(a), IpAddr::V6(b)) => a == b || a.to_ipv4_mapped() == b.to_ipv4(),
        _ => false,
    }
}

fn normalize_for_socket(address: IpAddr, ipv6_socket: bool) -> IpAddr {
    match (address, ipv6_socket) {
        (IpAddr::V4(ip), true) => IpAddr::V6(ip.to_ipv6_mapped()),
        (IpAddr::V6(ip), false) => match ip.to_ipv4_mapped() {
            Some(ipv4) => IpAddr::V4(ipv4),
            None => address,
        },
        _ => address,
    }
}

struct RelayShared {
    stop: AtomicBool,
    client_endpoint: Mutex<Option<SocketAddr>>,
    relay_endpoint: Mutex<SocketAddr>,
    target_endpoint: SocketAddr,
}

impl RelayShared {
    fn stopped(&self) -> bool {
        self.stop.load(Ordering::SeqCst)
    }
}

pub struct PreparedRelay {
    game_socket: UdpSocket,
    relay_socket: UdpSocket,
    control: TcpStream,
    shared: Arc<RelayShared>,
    pub local_port: u16,
}

pub struct RelayHandle {
    shared: Arc<RelayShared>,
}

impl RelayHandle {
    pub fn stop(&self) {
        self.shared.stop.store(true, Ordering::SeqCst);
    }
}

pub fn prepare_udp_relay(
    proxy: &ProxyConfig,
    target_host: &str,
    target_port: u16,
) -> Result<PreparedRelay, String> {
    let target_endpoint = resolve(target_host, target_port)?;
    let mut control = connect_prefer_ipv4(&proxy.host, proxy.port)?;
    control
        .set_read_timeout(Some(HANDSHAKE_TIMEOUT))
        .map_err(|error| error.to_string())?;
    handshake(&mut control, proxy)?;
    let game_socket = UdpSocket::bind(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 0))
        .map_err(|error| format!("не удалось открыть UDP-сокет для игры: {error}"))?;
    let control_local = control.local_addr().map_err(|error| error.to_string())?;
    // Локальный прокси: релей слушаем на 127.0.0.1, а не на всех интерфейсах.
    let bind_ip = if control_local.ip().is_loopback() {
        IpAddr::V4(Ipv4Addr::LOCALHOST)
    } else {
        control_local.ip()
    };
    let relay_socket = UdpSocket::bind(SocketAddr::new(bind_ip, 0))
        .map_err(|error| format!("не удалось открыть UDP-сокет релея: {error}"))?;
    let client_endpoint = relay_socket
        .local_addr()
        .map_err(|error| error.to_string())?;
    let relay_endpoint = udp_associate(&mut control, proxy, client_endpoint)?;
    control
        .set_read_timeout(Some(READ_TIMEOUT))
        .map_err(|error| error.to_string())?;
    game_socket
        .set_read_timeout(Some(READ_TIMEOUT))
        .map_err(|error| error.to_string())?;
    relay_socket
        .set_read_timeout(Some(READ_TIMEOUT))
        .map_err(|error| error.to_string())?;
    let local_port = game_socket
        .local_addr()
        .map_err(|error| error.to_string())?
        .port();
    Ok(PreparedRelay {
        shared: Arc::new(RelayShared {
            stop: AtomicBool::new(false),
            client_endpoint: Mutex::new(None),
            relay_endpoint: Mutex::new(relay_endpoint),
            target_endpoint,
        }),
        game_socket,
        relay_socket,
        control,
        local_port,
    })
}

impl PreparedRelay {
    pub fn stop(self) {
        self.shared.stop.store(true, Ordering::SeqCst);
    }

    pub fn start(self) -> RelayHandle {
        let shared = Arc::clone(&self.shared);
        let target_endpoint = self.shared.target_endpoint;
        let is_ipv6_relay = self
            .relay_socket
            .local_addr()
            .map(|addr| addr.is_ipv6())
            .unwrap_or(false);
        let upstream = Arc::clone(&self.shared);
        let game_socket = self.game_socket.try_clone();
        let relay_socket = self.relay_socket.try_clone();
        if let (Ok(game_socket), Ok(relay_socket)) = (game_socket, relay_socket) {
            thread::spawn(move || loop {
                if upstream.stopped() {
                    return;
                }
                let mut buffer = vec![0u8; 65536];
                let (size, source) = match game_socket.recv_from(&mut buffer) {
                    Ok(value) => value,
                    Err(_) => continue,
                };
                // Адрес клиента учится один раз — по первому пакету игры;
                // пакеты с других адресов выбрасываем.
                {
                    let mut guard = match upstream.client_endpoint.lock() {
                        Ok(guard) => guard,
                        Err(_) => return,
                    };
                    match *guard {
                        Some(current) if !same_address(current, source) => continue,
                        None => *guard = Some(source),
                        Some(_) => {}
                    }
                }
                let framed = frame_udp(target_endpoint, &buffer[..size]);
                let endpoint = match upstream.relay_endpoint.lock() {
                    Ok(guard) => {
                        let mut value = *guard;
                        value.set_ip(normalize_for_socket(value.ip(), is_ipv6_relay));
                        value
                    }
                    Err(_) => return,
                };
                let _ = relay_socket.send_to(&framed, endpoint);
            });
        } else {
            shared.stop.store(true, Ordering::SeqCst);
        }
        let downstream = Arc::clone(&shared);
        let game_socket = self.game_socket;
        let relay_socket = self.relay_socket;
        thread::spawn(move || loop {
            if downstream.stopped() {
                return;
            }
            let mut buffer = vec![0u8; 65536];
            let (size, source) = match relay_socket.recv_from(&mut buffer) {
                Ok(value) => value,
                Err(_) => continue,
            };
            // relay_endpoint зафиксирован ответом udp_associate:
            // всё, что приходит с другого адреса, — не наш прокси.
            let expected = match downstream.relay_endpoint.lock() {
                Ok(guard) => *guard,
                Err(_) => return,
            };
            if !same_address(expected, source) {
                continue;
            }
            let payload = parse_udp(&buffer[..size]).unwrap_or(&buffer[..size]);
            let client = match downstream.client_endpoint.lock() {
                Ok(guard) => *guard,
                Err(_) => return,
            };
            if let Some(target) = client {
                let _ = game_socket.send_to(payload, target);
            }
        });
        let mut control = self.control;
        let monitor = Arc::clone(&shared);
        thread::spawn(move || {
            let mut probe = [0u8; 1];
            loop {
                match control.read(&mut probe) {
                    Ok(0) => break,
                    Ok(_) => {}
                    Err(_) => {}
                }
                if monitor.stopped() {
                    break;
                }
            }
            monitor.stop.store(true, Ordering::SeqCst);
        });
        RelayHandle { shared }
    }
}

#[cfg(all(test, unix))]
mod relay_tests {
    use super::*;

    struct FakeSocks {
        addr: SocketAddr,
        shutdown: Arc<AtomicBool>,
    }

    fn spawn_fake_socks() -> FakeSocks {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let shutdown = Arc::new(AtomicBool::new(false));
        let flag = Arc::clone(&shutdown);
        thread::spawn(move || {
            while !flag.load(Ordering::SeqCst) {
                listener.set_nonblocking(true).ok();
                let (mut stream, _) = match listener.accept() {
                    Ok(value) => value,
                    Err(_) => {
                        thread::sleep(Duration::from_millis(20));
                        continue;
                    }
                };
                stream.set_nonblocking(false).ok();
                stream.set_read_timeout(Some(Duration::from_secs(5))).ok();
                thread::spawn(move || {
                    let mut greeting = [0u8; 2];
                    stream.read_exact(&mut greeting).ok();
                    let mut methods = vec![0u8; greeting[1] as usize];
                    if !methods.is_empty() {
                        stream.read_exact(&mut methods).ok();
                    }
                    if greeting[1] >= 1 {
                        stream.write_all(&[0x05, 0x00]).ok();
                    }
                    let mut head = [0u8; 4];
                    if stream.read_exact(&mut head).is_err() {
                        return;
                    }
                    let skip = match head[3] {
                        0x01 => 6,
                        0x04 => 18,
                        _ => return,
                    };
                    let mut rest = vec![0u8; skip];
                    stream.read_exact(&mut rest).ok();
                    let relay = UdpSocket::bind("127.0.0.1:0").unwrap();
                    let port = relay.local_addr().unwrap().port();
                    let mut reply = vec![0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1];
                    reply.push((port >> 8) as u8);
                    reply.push((port & 0xFF) as u8);
                    stream.write_all(&reply).ok();
                    let mut buffer = vec![0u8; 65536];
                    loop {
                        let (size, source) = match relay.recv_from(&mut buffer) {
                            Ok(value) => value,
                            Err(_) => continue,
                        };
                        if parse_udp(&buffer[..size]).is_some() {
                            let mut response = frame_udp(
                                SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 1212),
                                b"pong",
                            );
                            response[1] = 0x01;
                            relay.send_to(&response, source).ok();
                        }
                    }
                });
            }
        });
        FakeSocks { addr, shutdown }
    }

    #[test]
    fn probe_tcp_reaches_fake_socks() {
        let fake = spawn_fake_socks();
        let proxy = ProxyConfig {
            launcher: true,
            host: fake.addr.ip().to_string(),
            port: fake.addr.port(),
            ..Default::default()
        };
        assert!(probe_tcp(&proxy).unwrap() >= 1);
        fake.shutdown.store(true, Ordering::SeqCst);
    }

    #[test]
    fn probe_udp_associates_with_fake_socks() {
        let fake = spawn_fake_socks();
        let proxy = ProxyConfig {
            launcher: true,
            host: fake.addr.ip().to_string(),
            port: fake.addr.port(),
            ..Default::default()
        };
        probe_udp(&proxy).unwrap();
        fake.shutdown.store(true, Ordering::SeqCst);
    }

    #[test]
    fn udp_relay_roundtrip_through_fake_socks() {
        let fake = spawn_fake_socks();
        let proxy = ProxyConfig {
            launcher: true,
            host: fake.addr.ip().to_string(),
            port: fake.addr.port(),
            udp_relay: true,
            ..Default::default()
        };
        let relay = prepare_udp_relay(&proxy, "203.0.113.10", 1212).unwrap();
        let local_port = relay.local_port;
        let handle = relay.start();
        let client = UdpSocket::bind("127.0.0.1:0").unwrap();
        client
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        client
            .send_to(
                b"ping",
                SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), local_port),
            )
            .unwrap();
        let mut buffer = [0u8; 64];
        let (size, _) = client.recv_from(&mut buffer).unwrap();
        assert_eq!(&buffer[..size], b"pong");
        handle.stop();
        fake.shutdown.store(true, Ordering::SeqCst);
    }
}
