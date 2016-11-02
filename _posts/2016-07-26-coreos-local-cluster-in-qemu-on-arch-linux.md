---
layout: post
title: CoreOS local cluster in QEMU on Arch Linux
date: 2016-07-26 12:55:52 -0400
categories: articles
---

Introduction
============

CoreOS is a lightweight Linux-based OS for clustered deployments of containers. It can stand on its own but also works well with higher-level tools like Kubernetes.

Here I will walk through a process for running a small cluster of CoreOS VMs that will be booted over the network from another Arch Linux system. This should mostly be suitable for testing/dev.

The server named archpxe will provide TFTP. The server named archvmhost will provide HTTP (via nginx) and run the virtual machines. You could probably combine these roles on to a single server but that is not covered here.

I have tested this with QEMU version 2.6.0.

Set up the Network Boot Server
==============================

First, go configure your DHCP server to hand out the appropriate next-server IP and filename. If you're using pfSense, for example, you may find settings called "Next Server" (example: 192.168.5.243) and "Default BIOS file name" (pxelinux.0) under the Services-&gt;DHCP Server web interface page.

Now we will need a TFTP server.

## Set up TFTP

Here, we will:

-   Install the tftp-hpa package to provide the TFTP server.
-   Install the syslinux package to provide pxelinux.0 and dependencies as the initial boot target.
-   Download the CoreOS PXE image.
-   Create the pxelinux configuration.

```
pacman -S tftp-hpa
systemctl enable tftpd
systemctl start tftpd

pacman -S syslinux
cp /usr/lib/syslinux/bios/pxelinux.0 /srv/tftp/
cp /usr/lib/syslinux/bios/ldlinux.c32 /srv/tftp/

pacman -S wget
cd /srv/tftp
wget https://stable.release.core-os.net/amd64-usr/current/coreos_production_pxe.vmlinuz
wget https://stable.release.core-os.net/amd64-usr/current/coreos_production_pxe_image.cpio.gz
```

## Configure PXELINUX

Now we can create the pxelinux configuration. Note that we are passing the cloud-config-url kernel parameter.

```
mkdir /srv/tftp/pxelinux.cfg
```
```
# /srv/tftp/pxelinux.cfg/default
default coreos
prompt 1
timeout 15
display boot.msg

label coreos
  menu default
  kernel coreos_production_pxe.vmlinuz
  append initrd=coreos_production_pxe_image.cpio.gz cloud-config-url=http://archvmhost/coreos-cloud-config.yaml
```

Set up the Virtual Machine Host
===============================

## Set up nginx

Now let's install nginx on the archvmhost server to serve up the coreos-cloud-config.yaml file. The reason we are doing this is so that nginx can replace the $public_ipv4 placeholder in the coreos-cloud-config.yaml file with the remote client's IP address when it requests it over HTTP.

First, install nginx:

```
pacman -S nginx
```

Now we can create our nginx config, overwriting what is already there.

```
# /etc/nginx/nginx.conf
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    geo $dollar {
        default "$";
    }

    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80;
        server_name  localhost;

        location /coreos-cloud-config.yaml {
            root /srv/http;
            sub_filter '${dollar}private_ipv4' '$remote_addr';
            sub_filter_once off;
            sub_filter_types '*';
        }

        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }
    }
}
```

Here I'm only adding support for the $private_ipv4 substitution. In my case this is all on a local network so $remote_addr is an appropriate value to substitute. The $dollar variable is necessary to avoid nginx's variable substitution here, it's an ugly workaround but it works.

So what we've done here is configured nginx to replace any occurrences of $private_ipv4 in the requested file /coreos-cloud-config.yaml, with the IP address of the remote system ($remote_addr). If the file /srv/http/coreos-cloud-config.yaml contained 'Your IP is: $private_ipv4', then you could use curl/etc on another system and get a response saying 'Your IP is: 192.168.5.100', for example.

Now we can enable and start nginx.

```
systemctl enable nginx
systemctl start nginx
```

## Create a Bridge

In my case I want these systems on the same network segment as the host, so I'm going to create a bridge and then let QEMU create the tap device.

The Arch Linux wiki details a [number of options](https://wiki.archlinux.org/index.php/Network_bridge) for creating a bridge.
I am going to use systemd-networkd to create a permanent bridge named br0 with a physical interface of eno1.

First, I will create a few files to describe the network configuration.

```ini
# /etc/systemd/network/br0.netdev
[NetDev]
Name=br0
Kind=bridge
# Optionally specify a link address
# Useful if you have DHCP reservations (aka static DHCP)
MACAddress=01:23:45:67:89:AB
```

```ini
# /etc/systemd/network/br0.network
[Match]
Name=br0

[Network]
DHCP=ipv4
```
```ini
# /etc/systemd/network/br0-slave.network
[Match]
Name=eno1

[Network]
Bridge=br0
```

Now I need to disable dhcpcd, which I was using previously, and enable systemd-networkd instead.

```
systemctl disable dhcpcd
systemctl enable systemd-networkd
```

After a reboot (I don't recommend doing this remotely), connectivity should be back up as normal but with br0 having acquired a DHCP lease, rather than eno1.

Finally, we need to whitelist the bridge interface for QEMU:

```bash
mkdir -p /etc/qemu
echo 'allow br0' >> /etc/qemu/bridge.conf
```

## Enable KSM (Optional)

We can use [Kernel Samepage Merging](http://www.linux-kvm.org/page/KSM) to save on memory consumption. You can search the QEMU source for MADV_MERGEABLE to get an idea of what memory is shared.

```bash
# Enable KSM
echo 1 > /sys/kernel/mm/ksm/run
```

You may want to put this in a startup service to make it permanent.

Later on, after starting our virtual machines, we can see how much memory we have saved:

```bash
echo $(( $(cat /sys/kernel/mm/ksm/pages_sharing) * $(getconf PAGESIZE) )) | numfmt --to=iec-i
```

In my tests I was seeing ~4GiB saved with 20 CoreOS VMs. That may not seem like a ton but it definitely adds up when operating at scale. You can also see how much memory is being shared between the processes:

```bash
echo $(( $(cat /sys/kernel/mm/ksm/pages_shared) * $(getconf PAGESIZE) )) | numfmt --to=iec-i
```

For me this was ~219MiB. The chart below demonstrates that we have steeper memory usage growth without KSM.

<div id="ksm_curve_chart" style="width: 800px; height: 500px">
</div>

<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
<script type="text/javascript">
  google.charts.load('current', {'packages':['corechart']});
  google.charts.setOnLoadCallback(drawChart);

  function drawChart() {
    var data = google.visualization.arrayToDataTable([
      ['VMs', 'Without KSM', 'With KSM'],
      ['1',  384,      384],
      ['2',  768,      549],
      ['3',  1152,       714],
      ['4',  1536,      879],
      ['5',  1920,      1044],
      ['6',  2304,      1209],
      ['7',  2688,      1374],
      ['8',  3072,      1539],
      ['9',  3456,      1704],
      ['10',  3840,     1869],
      ['11',  4224,     2034],
      ['12',  4608,     2199],
      ['13',  4992,     2364],
      ['14',  5376,     2529],
      ['15',  5760,     2694],
      ['16',  6144,     2859],
      ['17',  6528,     3024],
      ['18',  6912,     3189],
      ['19',  7296,     3354],
      ['20',  7680,     3519],
    ]);

    var options = {
      title: 'Memory Usage of QEMU VMs With and Without KSM',
      curveType: 'function',
      legend: { position: 'bottom' },
      hAxis: { title: 'Number of VMs' },
      vAxis: { title: 'Memory Usage (MiB)' }
    };

    var chart = new google.visualization.LineChart(document.getElementById('ksm_curve_chart'));

    chart.draw(data, options);
  }
</script>

Create a Cloudinit Template
===========================

Finally we can create our cloudinit config template. I say template because we are going to put in a placeholder for `<DISCOVERY_URL>` that a script will replace when run.

You will want to substitute your own public key here for SSH access (username 'core'). Or you could create a separate user as documented in the CoreOS cloudinit docs.

`coreos-cloud-config.yaml.template`

```yaml
#cloud-config
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2[...] (REPLACE THIS)

coreos:
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start

  etcd2:
    discovery: <DISCOVERY_URL>
    advertise-client-urls: "http://$private_ipv4:2379"
    initial-advertise-peer-urls: "http://$private_ipv4:2380"
    listen-client-urls: "http://0.0.0.0:2379"
    listen-peer-urls: "http://$private_ipv4:2380"
```

`<DISCOVERY_URL>` would normally look something like this: `https://discovery.etcd.io/9e0aeb71f9b477f38e953f0050478666`. However, these URLs are one-time use (for each cluster) and require knowing the cluster size ahead of time. They are generated by going to a URL like: `https://discovery.etcd.io/new?size=3`.

Because of this, we put in a placeholder that our script will substitute after dynamically allocating a new discovery URL during invocation.

Start the Cluster
=================

First, we need qemu:

```
pacman -S qemu
```

Then, we'll put a little script together:

`start_coreos_cluster.sh`

```bash
#!/bin/bash
set -eu -o pipefail

USAGE="Usage: $0 <cloudinit-template> <count>"

STAGGER_TIME_SEC=1.0
VM_MEMORY_MB=1024
VM_CORES=1
BRIDGE_NAME=br0

function usage {
    echo "$USAGE"
    exit 1
}

[[ $# -ne 2 ]] && usage

cloudinit_template=$1
count=$2

discovery_url=$(curl -s "https://discovery.etcd.io/new?size=$count")
echo "Discovery URL: $discovery_url"

sed "s|<DISCOVERY_URL>|$discovery_url|" "$cloudinit_template" > /srv/http/coreos-cloud-config.yaml

for (( i = 1; i <= $count; i++ ))
do
    digits=$(printf "%02x" "$i")
    vm_name="coreos_$digits"
    vm_mac="52:54:00:12:34:$digits"
    qemu-system-x86_64 -name "$vm_name" \
        -m 1024 \
        -net bridge \
        -net nic,vlan=0,model=virtio,macaddr=$vm_mac \
        -boot n \
        -machine accel=kvm \
        -cpu host \
        -smp "$VM_CORES" \
        -display none &

    sleep "$STAGGER_TIME_SEC"
done
```

We can call this like so: `./start_coreos_cluster.sh coreos-cloud-config.yaml.template 3` to start a 3-node CoreOS cluster.

The script does the following:

-   Retrieves a new discovery URL based on the size of the cluster specified.
-   Substitutes that URL in place of the `<DISCOVERY_URL>` placeholder in the specified config template.
-   Starts a QEMU VM in the background that will network boot. The MAC addresses are specifically set to avoid conflicts.

There are also a few settings up at the top of the script:

| variable           | default | description                                |
|--------------------|---------|--------------------------------------------|
| STAGGER_TIME_SEC | 1.0     | Time, in seconds, between starting each VM |
| VM_MEMORY_MB     | 1024    | Amount of memory for each VM in MiB        |
| VM_CORES          | 1       | Number of processor cores for each VM      |
| BRIDGE_NAME       | br0     | Name of the network bridge device          |

Confirm Functionality
=====================

There are a few items to check that the cluster is healthy.

First, check the discovery URL in a browser or with curl. For example:

```
curl -s https://discovery.etcd.io/57de7e09a1376036179ca4b3092f40cc | jq
```
```json
{
  "action": "get",
  "node": {
    "key": "/_etcd/registry/57de7e09a1376036179ca4b3092f40cc",
    "dir": true,
    "nodes": [
      {
        "key": "/_etcd/registry/57de7e09a1376036179ca4b3092f40cc/3470e6055e4e1119",
        "value": "a1576454e3bf449d9fd98c3d6b28006a=http://192.168.5.236:2380",
        "modifiedIndex": 1149021445,
        "createdIndex": 1149021445
      },
      {
        "key": "/_etcd/registry/57de7e09a1376036179ca4b3092f40cc/dc0df5ec4a3f1c1f",
        "value": "002ce5c216ec446fad0fdf28c4f75b51=http://192.168.5.200:2380",
        "modifiedIndex": 1149021527,
        "createdIndex": 1149021527
      },
      {
        "key": "/_etcd/registry/57de7e09a1376036179ca4b3092f40cc/cd968f42a6e76ec6",
        "value": "c1dff243172643eea483aea66984545a=http://192.168.5.237:2380",
        "modifiedIndex": 1149021548,
        "createdIndex": 1149021548
      },
      {
        "key": "/_etcd/registry/57de7e09a1376036179ca4b3092f40cc/dec55d937871aa93",
        "value": "3ba8ca7970d64d87a395e668de7d8908=http://192.168.5.229:2380",
        "modifiedIndex": 1149021567,
        "createdIndex": 1149021567
      },
      {
        "key": "/_etcd/registry/57de7e09a1376036179ca4b3092f40cc/a365ceee28d65bb5",
        "value": "dd219995e6c04162b5520d7313148dfe=http://192.168.5.231:2380",
        "modifiedIndex": 1149021633,
        "createdIndex": 1149021633
      }
    ],
    "modifiedIndex": 1149020480,
    "createdIndex": 1149020480
  }
}
```
Here I'm piping the output to the 'jq' utility for pretty formatting. You can see all 3 nodes in the array have registered. If this were not the case, the nodes array would be empty or would not exist.

Another thing to do is to simply login to one of the CoreOS nodes and do something like:

```
etcdctl cluster-health
```

Then you may want to throw some data into etcd:

```
etcdctl mk /testing testdata
```

Now on other nodes, make sure the data is there:

```
etcdctl get /testing
```

or
```
curl -sL http://127.0.0.1:2379/v2/keys/testing
```
