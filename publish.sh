git checkout gh-pages
cp -r _book/* ./
git add -A .
git commit -sm "update generated book"
git push origin gh-pages
git checkout master
