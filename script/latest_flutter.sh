curl -s https://api.github.com/repos/flutter/flutter/tags | grep -oP '"name": "\K(.*)(?=")' | head -n 1
