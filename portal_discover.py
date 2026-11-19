#!/usr/bin/env python3
"""Auto-fill config.json: find the LAN interface, identify the PS5 via Remote
Play DDP discovery, and locate a powered-on Portal by Sony OUI. No sudo needed."""
import ipaddress, json, re, socket, subprocess, sys, threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRCH = b"SRCH * HTTP/1.1\r\ndevice-discovery-protocol-version:00030010\r\n"
# Sony Interactive Entertainment / Sony OUIs seen on PlayStation hardware.
SONY_OUIS = {
    '00:d9:d1', '00:19:c5', '78:c8:81', 'f8:46:1c', 'ac:9b:0a', 'd8:9e:3f',
    '5c:96:66', 'e0:ae:5e', 'a8:e3:ee', '9c:37:cb', '90:47:48', '04:5d:be',
}


def default_interface():
    out = subprocess.check_output(['/sbin/route', '-n', 'get', 'default'], text=True)
    m = re.search(r'interface:\s*(\S+)', out)
    if not m:
        sys.exit('No default IPv4 route found; connect to your LAN first.')
    iface = m.group(1)
    if not re.fullmatch(r'en[0-9]+', iface):
        sys.exit(f'Default interface {iface!r} is not a Mac en* interface.')
    return iface


def own_subnet(iface):
    out = subprocess.check_output(['/sbin/ifconfig', iface], text=True)
    m = re.search(r'inet (\d+\.\d+\.\d+\.\d+) netmask (0x[0-9a-f]+)', out)
    if not m:
        sys.exit(f'No IPv4 address on {iface}.')
    mask = str(ipaddress.IPv4Address(int(m.group(2), 16)))
    net = ipaddress.IPv4Network(f'{m.group(1)}/{mask}', strict=False)
    if net.prefixlen < 22:
        sys.exit(f'{net} looks too large to sweep; configure config.json manually.')
    return net


def sweep(net, iface):
    # Ping every host only to prime ARP resolution; a resolved ARP entry is
    # itself proof of a live device (ICMP may be filtered on some gadgets).
    slots = threading.BoundedSemaphore(48)

    def probe(ip):
        with slots:
            subprocess.run(['/sbin/ping', '-c', '1', '-W', '500', str(ip)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    threads = [threading.Thread(target=probe, args=(ip,), daemon=True)
               for ip in net.hosts()]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    table = subprocess.check_output(['/usr/sbin/arp', '-an', '-i', iface], text=True)
    found = {}
    for m in re.finditer(r'\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-f:]+)', table):
        ip, mac = m.groups()
        if mac != 'ff:ff:ff:ff:ff:ff':
            found[ip] = ':'.join(f'{int(x, 16):02x}' for x in mac.split(':'))
    return found


def ddp_srch(ip, timeout=0.8):
    """Return the DDP reply fields if the host answers as a PlayStation."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        s.sendto(SRCH, (ip, 9302))
        data, _ = s.recvfrom(4096)
        fields = {}
        for line in data.decode(errors='replace').splitlines():
            if ':' in line:
                k, v = line.split(':', 1)
                fields[k.strip()] = v.strip()
        return fields
    except OSError:
        return None
    finally:
        s.close()


def is_sony(mac):
    return ':'.join(mac.split(':')[:3]) in SONY_OUIS


def pick(candidates, what):
    if len(candidates) == 1:
        return candidates[0]
    print(f'More than one possible {what}:')
    for i, ip in enumerate(candidates):
        print(f'  {i + 1}) {ip}')
    choice = input(f'Select {what} [1-{len(candidates)}]: ').strip()
    return candidates[int(choice) - 1]


def main():
    iface = default_interface()
    net = own_subnet(iface)
    print(f'Interface {iface}, sweeping {net} ...')
    hosts = sweep(net, iface)
    print(f'{len(hosts)} live devices.')

    ps5 = None
    sony = [ip for ip, mac in sorted(hosts.items(), key=lambda kv: ipaddress.IPv4Address(kv[0]))
            if is_sony(mac)]
    for ip in sony or sorted(hosts, key=ipaddress.IPv4Address):
        reply = ddp_srch(ip)
        if reply and reply.get('host-type', '').upper().startswith('PS5'):
            ps5 = ip
            print(f'PS5 found: {ip} ({reply.get("host-name", "?")}, '
                  f'system-version {reply.get("system-version", "?")})')
            break
    if not ps5:
        sys.exit('No PS5 answered Remote Play discovery. Wake the PS5 and re-run.')

    portals = [ip for ip in sony if ip != ps5]
    if not portals:
        others = [ip for ip in sorted(hosts, key=ipaddress.IPv4Address)
                  if ip != ps5 and ddp_srch(ip) is None]
        sys.exit('PS5 found but no powered-on Portal detected (it sleeps off Wi-Fi). '
                 'Turn the Portal on, then re-run. Other live devices: '
                 + (', '.join(others[:20]) or 'none'))
    portal = pick(portals, 'Portal')

    config = {'interface': iface, 'ps5_ip': ps5, 'portal_ip': portal}
    (ROOT / 'config.json').write_text(json.dumps(config, indent=2) + '\n')
    print(f'Wrote config.json: {config}')

    auto_path = ROOT / 'auto-config.json'
    if auto_path.exists():
        profile = '65'
        try:
            profile = json.loads(auto_path.read_text()).get('profile', profile)
        except (OSError, ValueError):
            pass
        auto_path.write_text(json.dumps({
            'network': config, 'profile': profile,
            'ps5_mac': hosts[ps5], 'portal_mac': hosts[portal]}, indent=2) + '\n')
        print('Updated auto-config.json too. Restart the service: '
              'sudo launchctl kickstart -k system/com.portalbitrate.auto')

    print('Tip: give the PS5 and Portal DHCP reservations in your router so these '
          'addresses stay put.')


if __name__ == '__main__':
    main()
