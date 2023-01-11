#!/bin/sh -l

set -e # if a command fails it stops the execution
set -u # script fails if trying to access to an undefined variable

echo "[+] Action start"
SOURCE_BEFORE_DIRECTORY="${1}"
SOURCE_DIRECTORY="${2}"
DESTINATION_GITHUB_USERNAME="${3}"
DESTINATION_REPOSITORY_NAME="${4}"
GITHUB_SERVER="${5}"
USER_EMAIL="${6}"
USER_NAME="${7}"
DESTINATION_REPOSITORY_USERNAME="${8}"
TARGET_BRANCH="${9}"
COMMIT_MESSAGE="${10}"
TARGET_DIRECTORY="${11}"

if [ -z "$DESTINATION_REPOSITORY_USERNAME" ]; then
	DESTINATION_REPOSITORY_USERNAME="$DESTINATION_GITHUB_USERNAME"
fi

if [ -z "$USER_NAME" ]; then
	USER_NAME="$DESTINATION_GITHUB_USERNAME"
fi

# Verify that there (potentially) some access to the destination repository
# and set up git (with GIT_CMD variable) and GIT_CMD_REPOSITORY
if [ -n "${SSH_DEPLOY_KEY:=}" ]; then
	echo "[+] Usando SSH_DEPLOY_KEY"

	# Inspired by https://github.com/leigholiver/commit-with-deploy-key/blob/main/entrypoint.sh , thanks!
	mkdir --parents "$HOME/.ssh"
	DEPLOY_KEY_FILE="$HOME/.ssh/deploy_key"
	echo "${SSH_DEPLOY_KEY}" >"$DEPLOY_KEY_FILE"
	chmod 600 "$DEPLOY_KEY_FILE"

	SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
	ssh-keyscan -H "$GITHUB_SERVER" >"$SSH_KNOWN_HOSTS_FILE"

	export GIT_SSH_COMMAND="ssh -i "$DEPLOY_KEY_FILE" -o UserKnownHostsFile=$SSH_KNOWN_HOSTS_FILE"

	GIT_CMD_REPOSITORY="git@$GITHUB_SERVER:$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git"

elif [ -n "${API_TOKEN_GITHUB:=}" ]; then
	echo "[+] Usando API_TOKEN_GITHUB"
	GIT_CMD_REPOSITORY="https://$DESTINATION_REPOSITORY_USERNAME:$API_TOKEN_GITHUB@$GITHUB_SERVER/$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git"
else
	echo "::error::API_TOKEN_GITHUB e SSH_DEPLOY_KEY estão vazios. Por favor, preencha um (recomendado o SSH_DEPLOY_KEY)"
	exit 1
fi

CLONE_DIR=$(mktemp -d)

echo "[+] Versão do GIT"
git --version

echo "[+] Clonando o repositório git de destino $DESTINATION_REPOSITORY_NAME"
# Setup git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

{
	git clone --single-branch --depth 1 --branch "$TARGET_BRANCH" "$GIT_CMD_REPOSITORY" "$CLONE_DIR"
} || {
	echo "::error::Não foi possível clonar o repositório de destino. Comando:"
	echo "::error::git clone --single-branch --branch $TARGET_BRANCH $GIT_CMD_REPOSITORY $CLONE_DIR"
	echo "::error::(Observe que, se eles existirem, USER_NAME e API_TOKEN serão editados pelo GitHub)"
	echo "::error::Verifique se o repositório de destino existe E se contém o nome da ramificação de destino e se é acessível pela API_TOKEN GITHUB OU SSH DEPLOY_KEY"
	exit 1
}

ls -la "$CLONE_DIR"

TEMP_DIR=$(mktemp -d)
# This mv has been the easier way to be able to remove files that were there
# but not anymore. Otherwise we had to remove the files from "$CLONE_DIR",
# including "." and with the exception of ".git/"
mv "$CLONE_DIR/.git" "$TEMP_DIR/.git"

# $TARGET_DIRECTORY is '' by default
ABSOLUTE_TARGET_DIRECTORY="$CLONE_DIR/$TARGET_DIRECTORY/"

echo "[+] Deletando $ABSOLUTE_TARGET_DIRECTORY"
rm -rf "$ABSOLUTE_TARGET_DIRECTORY"

echo "[+] Criando (agora vazio) $ABSOLUTE_TARGET_DIRECTORY"
mkdir -p "$ABSOLUTE_TARGET_DIRECTORY"

echo "[+] Listando a localização atual do diretório"
ls -al

echo "[+] Localização raiz da listagem"
ls -al /

mv "$TEMP_DIR/.git" "$CLONE_DIR/.git"

echo "[+] Listar o conteúdo de $SOURCE_DIRECTORY"
ls "$SOURCE_DIRECTORY"

echo "[+] Verificando se local $SOURCE_DIRECTORY existe"
if [ ! -d "$SOURCE_DIRECTORY" ]; then
	echo "ERROR: $SOURCE_DIRECTORY não existe"
	echo "Este diretório precisa existir quando o push-to-another-repository é executado"
	echo
	echo "No exemplo, ele é criado por ./build.sh: https://github.com/cpina/push-to-another-repository-example/blob/main/.github/workflows/ci.yml#L19"
	echo
	echo "Se você deseja copiar um diretório existente no repositório de origem"
	echo "para o repositório de destino: você precisa clonar o repositório de origem"
	echo "em uma etapa anterior na mesma seção de compilação. Por exemplo usando"
	echo "actions/checkout@v2. Veja: https://github.com/cpina/push-to-another-repository-example/blob/main/.github/workflows/ci.yml#L16"
	exit 1
fi

echo "[+] Copiando o conteúdo da pasta do repositório de origem $SOURCE_DIRECTORY para a pasta $TARGET_DIRECTORY no repositório git $DESTINATION_REPOSITORY_NAME"
cp -ra "$SOURCE_DIRECTORY"/. "$CLONE_DIR/$TARGET_DIRECTORY"
cd "$CLONE_DIR"

echo "[+] Arquivos que serão enviados"
ls -la

ORIGIN_COMMIT="https://$GITHUB_SERVER/$GITHUB_REPOSITORY/commit/$GITHUB_SHA"
COMMIT_MESSAGE="${COMMIT_MESSAGE/ORIGIN_COMMIT/$ORIGIN_COMMIT}"
COMMIT_MESSAGE="${COMMIT_MESSAGE/\$GITHUB_REF/$GITHUB_REF}"

echo "[+] Definir diretório é seguro ($CLONE_DIR)"
# Related to https://github.com/cpina/github-action-push-to-another-repository/issues/64 and https://github.com/cpina/github-action-push-to-another-repository/issues/64
# TODO: review before releasing it as a version
git config --global --add safe.directory "$CLONE_DIR"

echo "[+] Adicionando git commit"
git add .

echo "[+] git status:"
git status

echo "[+] git diff-index:"
# git diff-index : to avoid doing the git commit failing if there are no changes to be commit
git diff-index --quiet HEAD || git commit --message "$COMMIT_MESSAGE"

echo "[+] Enviando git commit"
# --set-upstream: sets de branch when pushing to a branch that does not exist
git push "$GIT_CMD_REPOSITORY" --set-upstream "$TARGET_BRANCH"
