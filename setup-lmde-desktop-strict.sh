#!/bin/bash

set -e

# Install nala
sudo apt-get update
sudo apt-get install -y nala

# Update and upgrade Linux distro using nala
sudo nala update && sudo nala upgrade -y

# Install additional system packages
sudo nala install -y \
  gnome-font-viewer \
  tealdeer \
  vlc \
  Fastfetch \
  transmission \
  gimp \
  filezilla \
  neovim \
  numix-icon-theme \
  ncdu \
  ffmpeg \
  gnome-tweaks \
  p7zip \
  unrar \
  wget \
  curl \
  git \
  autofs \
  fonts-font-awesome \
  htop \
  tmux \
  zsh \
  zsh-autosuggestions \
  zsh-syntax-highlighting \
  ffmpegthumbnailer \
  nemo-media-columns \
  

# Download and install JDownloader
https://jdownloader.org/jdownloader2#selection=linux
https://mega.nz/file/qU1TCYjL#g8a05FYWPGyqFgy1QWQ9L5nScEOmOU6iZh1eDhSn-sk

# Grant executable permission for the downloaded script
chmod +x JDownloader2Setup*.sh

#Then, run the script to launch the installer wizard
./JDownloader2Setup*.sh

# Download and install MesloLG Nerd Font
echo "Installing MesloLG Nerd Font..."
wget -O /tmp/Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip
sudo unzip -o /tmp/Meslo.zip -d /usr/local/share/fonts
sudo fc-cache -fv

# Check zsh version
zsh --version

# Make zsh the default shell
chsh -s $(which zsh)

# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install Powerlevel10K
git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k

# Install autosuggestions plugin
git clone https://github.com/zsh-users/zsh-autosuggestions.git $ZSH_CUSTOM/plugins/zsh-autosuggestions

# Install zsh-syntax-highlighting plugin
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting

# Install fast-syntax-highlighting plugin
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting

# Install zsh-autocomplete plugin
git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git $ZSH_CUSTOM/plugins/zsh-autocomplete

# Enable plugins in .zshrc
sed -i 's/^plugins=(.*)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete)/' ~/.zshrc || \
echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete)' >> ~/.zshrc

#Change ZSH_THERE to Powerlevel10k
ZSH_THEME="powerlevel10k/powerlevel10k"

echo "All steps completed. Restart your terminal or run 'zsh' to begin."

#To enable double-click renaming of files and folders in Linux Mint, 
#Nemo setting for double-click rename on LMDE
gsettings set org.nemo.preferences click-policy 'double'

#Verify the new setting
gsettings get org.nemo.preferences click-policy

#Restart Nemo to apply
nemo -q

Wallpaper https://alphacoders.com/
https://www.youtube.com/watch?v=Q_Uoe5H4ORs


# Setup Local Firewall

# Videos to watch after installing
https://www.youtube.com/watch?v=TrbB0WwywOQ
https://www.youtube.com/watch?v=XYDQK5i0tmY
https://www.youtube.com/watch?v=QwFxoDCXlM8
https://www.youtube.com/watch?v=kV8Hu54zhbA&t=1s
