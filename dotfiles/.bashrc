#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# RochaOS aliases
alias ls='ls --color=auto'
alias ll='ls -la'
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias search='pacman -Ss'
neofetch
export PATH="$HOME/.npm-global/bin:$HOME/bin:$PATH"
alias lapce='GDK_BACKEND=x11 WINIT_UNIX_BACKEND=x11 lapce'
alias lapce='env GDK_BACKEND=x11 WINIT_UNIX_BACKEND=x11 lapce'
export PATH="$HOME/.local/bin:$PATH"
