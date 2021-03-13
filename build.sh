##########################################################################
# File Name: build.sh
# Author: amoscykl
# mail: amoscykl980629@163.com
# Created Time: Sat 13 Mar 2021 21:50:25 +08
#########################################################################
#!/bin/zsh

gitbook build
git checkout gh-pages
cp -r ./_book/* ./
git commit -m "update"
git push origin gh-pages
git checkout master
