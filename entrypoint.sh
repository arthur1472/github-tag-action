#!/bin/bash

set -eo pipefail

#cat /etc/ssh/ssh_config
#cat ~/.ssh/config
#ls -al /github/workspace/
#ls -al /github/workspace/.git/
#cat /github/workspace/.git/config
#echo "$HOME"
#echo "$GIT_SSH_COMMAND"
#exit

# config
default_semvar_bump=${DEFAULT_BUMP:-minor}
default_branch=${DEFAULT_BRANCH:-$GITHUB_BASE_REF} # get the default branch from github runner env vars
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master,main}
custom_tag=${CUSTOM_TAG:-}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
git_api_tagging=${GIT_API_TAGGING:-true}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}
prerelease=${PRERELEASE:-false}
suffix=${PRERELEASE_SUFFIX:-beta}
verbose=${VERBOSE:-false}
major_string_token=${MAJOR_STRING_TOKEN:-#major}
minor_string_token=${MINOR_STRING_TOKEN:-#minor}
patch_string_token=${PATCH_STRING_TOKEN:-#patch}
none_string_token=${NONE_STRING_TOKEN:-#none}
branch_history=${BRANCH_HISTORY:-compare}
# since https://github.blog/2022-04-12-git-security-vulnerability-announced/ runner uses?
git config --global --add safe.directory /github/workspace

cd "${GITHUB_WORKSPACE}/${source}" || exit 1

echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tDEFAULT_BRANCH: ${default_branch}"
echo -e "\tWITH_V: ${with_v}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tGIT_API_TAGGING: ${git_api_tagging}"
echo -e "\tINITIAL_VERSION: ${initial_version}"
echo -e "\tTAG_CONTEXT: ${tag_context}"
echo -e "\tPRERELEASE: ${prerelease}"
echo -e "\tPRERELEASE_SUFFIX: ${suffix}"
echo -e "\tVERBOSE: ${verbose}"
echo -e "\tMAJOR_STRING_TOKEN: ${major_string_token}"
echo -e "\tMINOR_STRING_TOKEN: ${minor_string_token}"
echo -e "\tPATCH_STRING_TOKEN: ${patch_string_token}"
echo -e "\tNONE_STRING_TOKEN: ${none_string_token}"
echo -e "\tBRANCH_HISTORY: ${branch_history}"

# verbose, show everything
if $verbose
then
    set -x
fi

setOutput() {
    echo "${1}=${2}" >> "${GITHUB_OUTPUT}"
}

echo "Adding SSH key and running SSH agent"

touch $RUNNER_TEMP/id_ed25519
chmod 400 $RUNNER_TEMP/id_ed25519
#touch ~/.ssh/config
#chmod 600 ~/.ssh/config

cat > $RUNNER_TEMP/id_ed25519 << EOF
$SSH_KEY
EOF

cat > $RUNNER_TEMP/config << EOF
Host github.com
    IdentityFile $RUNNER_TEMP/id_ed25519
    IdentitiesOnly yes
    ForwardAgent yes
EOF

ssh-keyscan -t rsa github.com >> $RUNNER_TEMP/known_hosts
ssh-keyscan -t ed25519 github.com >> $RUNNER_TEMP/known_hosts

# date added at 2023-10-21, keys found at https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" >> $RUNNER_TEMP/known_hosts
echo "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=" >> $RUNNER_TEMP/known_hosts
echo "github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=" >> $RUNNER_TEMP/known_hosts

eval `ssh-agent -s`

ssh-add -D

ssh-add $RUNNER_TEMP/id_ed25519
#ssh-keyscan github.com >> ~/.ssh/known_hosts

echo "added SSH key"

#ssh -v github.com

#ssh -T git@github.com

current_branch=$(git rev-parse --abbrev-ref HEAD)

pre_release="$prerelease"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    # check if ${current_branch} is in ${release_branches} | exact branch match
    if [[ "$current_branch" == "$b" ]]
    then
        pre_release="false"
    fi
    # verify non specific branch names like  .* release/* if wildcard filter then =~
    if [ "$b" != "${b//[\[\]|.? +*]/}" ] && [[ "$current_branch" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

echo "fetching tags"

# fetch tags
git fetch --tags

echo "fetched tags"

tagFmt="^v?[0-9]+\.[0-9]+\.[0-9]+$"
preTagFmt="^v?[0-9]+\.[0-9]+\.[0-9]+(-$suffix\.[0-9]+)$"

# get the git refs
git_refs=
case "$tag_context" in
    *repo*)
        git_refs=$(git for-each-ref --sort=-v:refname --format '%(refname:lstrip=2)')
        ;;
    *branch*)
        git_refs=$(git tag --list --merged HEAD --sort=-committerdate)
        ;;
    * ) echo "Unrecognised context"
        exit 1;;
esac

# get the latest tag that looks like a semver (with or without v)
matching_tag_refs=$( (grep -E "$tagFmt" <<< "$git_refs") || true)
matching_pre_tag_refs=$( (grep -E "$preTagFmt" <<< "$git_refs") || true)
tag=$(head -n 1 <<< "$matching_tag_refs")
pre_tag=$(head -n 1 <<< "$matching_pre_tag_refs")

# if there are none, start tags at INITIAL_VERSION
if [ -z "$tag" ]
then
    if $with_v
    then
        tag="v$initial_version"
    else
        tag="$initial_version"
    fi
    if [ -z "$pre_tag" ] && $pre_release
    then
        if $with_v
        then
            pre_tag="v$initial_version"
        else
            pre_tag="$initial_version"
        fi
    fi
fi

# get current commit hash for tag
tag_commit=$(git rev-list -n 1 "$tag" || true )
# get current commit hash
commit=$(git rev-parse HEAD)
# skip if there are no new commits for non-pre_release
if [ "$tag_commit" == "$commit" ]
then
    echo "No new commits since previous tag. Skipping..."
    setOutput "new_tag" "$tag"
    setOutput "tag" "$tag"
    exit 0
fi

# sanitize that the default_branch is set (via env var when running on PRs) else find it natively
if [ -z "${default_branch}" ] && [ "$branch_history" == "full" ]
then
    echo "The DEFAULT_BRANCH should be autodetected when tag-action runs on on PRs else must be defined, See: https://github.com/anothrNick/github-tag-action/pull/230, since is not defined we find it natively"
    default_branch=$(git branch -rl '*/master' '*/main' | cut -d / -f2)
    echo "default_branch=${default_branch}"
    # re check this
    if [ -z "${default_branch}" ]
    then
        echo "::error::DEFAULT_BRANCH must not be null, something has gone wrong."
        exit 1
    fi
fi

# get the merge commit message looking for #bumps
declare -A history_type=(
    ["last"]="$(git show -s --format=%B)" \
    ["full"]="$(git log "${default_branch}"..HEAD --format=%B)" \
    ["compare"]="$(git log "${tag_commit}".."${commit}" --format=%B)" \
)
log=${history_type[${branch_history}]}
printf "History:\n---\n%s\n---\n" "$log"

case "$log" in
    *$major_string_token* ) new=$(semver -i major "$tag"); part="major";;
    *$minor_string_token* ) new=$(semver -i minor "$tag"); part="minor";;
    *$patch_string_token* ) new=$(semver -i patch "$tag"); part="patch";;
    *$none_string_token* )
        echo "Default bump was set to none. Skipping..."
        setOutput "old_tag" "$tag"
        setOutput "new_tag" "$tag"
        setOutput "tag" "$tag"
        setOutput "part" "$default_semvar_bump"
        exit 0;;
    * )
        if [ "$default_semvar_bump" == "none" ]
        then
            echo "Default bump was set to none. Skipping..."
            setOutput "old_tag" "$tag"
            setOutput "new_tag" "$tag"
            setOutput "tag" "$tag"
            setOutput "part" "$default_semvar_bump"
            exit 0
        else
            new=$(semver -i "${default_semvar_bump}" "$tag")
            part=$default_semvar_bump
        fi
        ;;
esac

if $pre_release
then
    # get current commit hash for tag
    pre_tag_commit=$(git rev-list -n 1 "$pre_tag" || true)
    # skip if there are no new commits for pre_release
    if [ "$pre_tag_commit" == "$commit" ]
    then
        echo "No new commits since previous pre_tag. Skipping..."
        setOutput "new_tag" "$pre_tag"
        setOutput "tag" "$pre_tag"
        exit 0
    fi
    # already a pre-release available, bump it
    if [[ "$pre_tag" =~ $new ]] && [[ "$pre_tag" =~ $suffix ]]
    then
        if $with_v
        then
            new=v$(semver -i prerelease "${pre_tag}" --preid "${suffix}")
        else
            new=$(semver -i prerelease "${pre_tag}" --preid "${suffix}")
        fi
        echo -e "Bumping ${suffix} pre-tag ${pre_tag}. New pre-tag ${new}"
    else
        if $with_v
        then
            new="v$new-$suffix.0"
        else
            new="$new-$suffix.0"
        fi
        echo -e "Setting ${suffix} pre-tag ${pre_tag} - With pre-tag ${new}"
    fi
    part="pre-$part"
else
    if $with_v
    then
        new="v$new"
    fi
    echo -e "Bumping tag ${tag} - New tag ${new}"
fi

# as defined in readme if CUSTOM_TAG is used any semver calculations are irrelevant.
if [ -n "$custom_tag" ]
then
    new="$custom_tag"
fi

# set outputs
setOutput "new_tag" "$new"
setOutput "part" "$part"
setOutput "tag" "$new" # this needs to go in v2 is breaking change
setOutput "old_tag" "$tag"

# dry run exit without real changes
if $dryrun
then
    exit 0
fi

echo "EVENT: creating local tag $new"
# create local git tag
git tag -f "$new" || exit 1
echo "EVENT: pushing tag $new to origin"

if $git_api_tagging
then
    # use git api to push
    dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
    full_name=$GITHUB_REPOSITORY
    git_refs_url=$(jq .repository.git_refs_url "$GITHUB_EVENT_PATH" | tr -d '"' | sed 's/{\/sha}//g')

    echo "$dt: **pushing tag $new to repo $full_name"

    git_refs_response=$(
    curl -s -X POST "$git_refs_url" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d @- << EOF
{
    "ref": "refs/tags/$new",
    "sha": "$commit"
}
EOF
)

    git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

    echo "::debug::${git_refs_response}"
    if [ "${git_ref_posted}" = "refs/tags/${new}" ]
    then
        exit 0
    else
        echo "::error::Tag was not created properly."
        exit 1
    fi
else
    # use git cli to push
    git push -f origin "$new" || exit 1
fi