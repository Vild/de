FROM wild/archlinux-dlang
MAINTAINER Dan Printzell <me@vild.io>

RUN pacman -Syyu fontconfig sdl2 --noprogressbar --noconfirm