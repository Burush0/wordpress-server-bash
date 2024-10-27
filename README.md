# wordpress-server-bash
A bash script that deploys Wordpress on Apache2 behind an Nginx proxy.

This is a continuation of the first part of the DevOps series, except this time I have streamlined and automated the process. If you want to know exactly what is going on and what the script does, check out [this](https://github.com/Burush0/wordpress-ubuntu-server) repo.

# Prerequisites:
- An [Ubuntu Server](https://ubuntu.com/download/server) installation, preferably fresh. I did mine inside a VMWare Workstation virtual machine.
- A way to generate SSH keys on your host machine. In my case of Windows 10, I had [Git](https://gitforwindows.org/) installed, that can also be achieved with [PuTTY](https://www.putty.org/).

# Setup:
## 1. Setup SSH connection between guest (VM) and host (your PC):

### 1.1. Install OpenSSH Server:

```
sudo apt install openssh-server -y
```

### 1.2. Generate an SSH key on your host machine:
```
ssh-keygen -t rsa -b 4096
```
- -t stands for type. RSA is the default type.
 
- -b stands for bits. By default the key is 3072 bits long. 4096 bits = stronger security.

You will be prompted to come up with a passphrase, it's optional but recommended.

Once you do that, a public-private keypair will be generated in .ssh in your user directory.

### 1.3. Send the public part of the key to the guest. 

```
ssh-copy-id <remote-user>@<server-ip>
```
The variables in this command will depend on the guest installation, your remote-user should match the username that you specified during the installation, and the server IP can be found by running the command `ip address` on the guest machine (at least the local IP, for remote SSH connections you will likely be given the machine's IP (duh))

Also, just in case, if a variable is specified like `<x>`, if you pass it in, you write it without the angle brackets. E.g. `x = 123, y = 456, <x>@<y>` becomes `123@456`. 

After you enter the `ssh-copy-id` command, you will be prompted to enter the password of your guest machine's user. Not the SSH passphrase! After you enter it, the public part of the key will be copied and you should be able to SSH over to guest now using
```
ssh <remote-user>@<server-ip>
```
This time, it will ask for the SSH passphrase and not the user password. You should be able to connect to the server now.

## 2. Specify a local domain name

In `/etc/hosts` file on your system (For Windows, that would be `C:/Windows/System32/drivers/etc/hosts`), add in a line that looks like this:
```
<server-ip> <domain-name>
```
To give a more specific example, my local server ip was `192.168.139.134` and the domain name I chose was `testdomain.com`, so the line looked like:
```
192.168.139.134 testdomain.com
```
Save changes to the file, needs administrator privileges (which means you might need to run Notepad as admin).

## 3. Run the script on the guest machine

### 3.1. Clone the repo and navigate to the folder
```
git clone https://github.com/Burush0/wordpress-server-bash.git
cd wordpress-server-bash
```
### 3.2. Make it executable
```
sudo chmod +x script.sh
```

### 3.3. Run it with specified arguments
```
sudo ./script.sh <DB_PASSWORD> <SERVER_DOMAIN> 
```
e.g.
```
sudo ./script.sh qwe123 testdomain.com
```

And that's it! You should have a working Wordpress deployment at `https://<SERVER_NAME>/wordpress/`

Note: When automatically creating the SSL certificate, I have specified my information with the flag `-subj`. If you would like to have your own information there, dig into the script file and edit it there. I didn't want to have a whole bunch of arguments.

The script is NOT idempotent, so running it multiple times will cause issues. Sorry about that, maybe I get to fixing that later but it's not on my priority list. Cheers.
