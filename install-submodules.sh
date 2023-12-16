mkdir $HOME/.ssh
touch $HOME/.ssh/id_rsa
chmod 600 $HOME/.ssh/id_rsa

git config --global url."git@github.com:".insteadOf "https://github.com/"

echo "$SSH_KEY_AAVE_V3_CORE" > $HOME/.ssh/id_rsa
git submodule update --init --recursive lib/aave-v3-core

git submodule update --init --recursive
