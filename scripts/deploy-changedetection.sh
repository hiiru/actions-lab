#!/bin/bash
#############################################################################################################
#Script Name  : deploy-changedetection.sh
#Description	: Checks for changes and determinate what has to be deployed.
#               It checks git diff for the Host project, and uses dotnet affects for other projects
#############################################################################################################
# Script variables
DEBUG=0
DEPLOY_API=0
DEPLOY_WEB=0

# usage and argument handling
usage() {
    echo "Usage: $0 [-r <gitReference>]" 1>&2;
    exit 1;
}

while getopts r:hd flag
do
    case "${flag}" in
        r) GIT_REFERENCE=${OPTARG};;
        h) usage ;;
        d) DEBUG=1 && echo "DEBUG output enabled" ;;
        *) usage ;;
    esac
done

if [ -z ${GIT_REFERENCE+x} ];
then
    GIT_REFERENCE=main
fi

if [ $DEBUG -eq 1 ]; then
    echo "git reference used for change detection: $GIT_REFERENCE"
fi

check_changed_host() {
    if [ $DEBUG -eq 1 ]; then
        echo "check_changed_host: checks git diff"
    fi
    git diff --quiet $GIT_REFERENCE -- src/Host
    local retVal=$?
    if [ $retVal -eq 0 ]; then
        if [ $DEBUG -eq 1 ]; then
            echo "check_changed_host: Host unchanged"
        fi
        return 1
    elif [ $retVal -eq 1 ]; then
        if [ $DEBUG -eq 1 ]; then
            echo "check_changed_host: Host changed"
        fi
        DEPLOY_API=1
        DEPLOY_WEB=1

        if [ ! -z "$GITHUB_STEP_SUMMARY" ];
        then
          echo "check_changed_host: Host changed, deploying both" >> "$GITHUB_STEP_SUMMARY"
        fi
        return 0
    else
    echo "check_changed_host: Error: unknown exit code from git diff: $retVal"
    exit 100
    fi
}

check_changed_projects() {
    if [ $DEBUG -eq 1 ]; then
        echo "check_changed_projects: checking dotnet affected"
    fi
    dotnet affected -f json --from $GIT_REFERENCE
    if [ ! -f affected.json ]; then
        if [ $DEBUG -eq 1 ]; then
            echo "check_changed_projects: no affected.json file generated"
        fi
        if [ ! -z "$GITHUB_STEP_SUMMARY" ];
        then
          echo "No changes detected (no affected.js file generated)" >> "$GITHUB_STEP_SUMMARY"
        fi
        return 1
    fi
    local changed=0
    local affected=()
    mapfile -t affected < <( jq -r '.[].Name' affected.json )
    for a in "${affected[@]}" ; do
        if [[ $a == Api ]]; then
            if [ $DEBUG -eq 1 ]; then
                echo "check_changed_projects: Api changed"
            fi
            DEPLOY_API=1
            changed=1
            if [ ! -z "$GITHUB_STEP_SUMMARY" ];
            then
              echo "* $a changed" >> "$GITHUB_STEP_SUMMARY"
            fi
        elif [ $a == Web ]; then
            if [ $DEBUG -eq 1 ]; then
                echo "check_changed_projects: Web changed"
            fi
            DEPLOY_WEB=1
            changed=1
            if [ ! -z "$GITHUB_STEP_SUMMARY" ];
            then
              echo "* $a changed" >> "$GITHUB_STEP_SUMMARY"
            fi
        fi
        if [[ $DEPLOY_API -eq 1 ]] && [[ DEPLOY_WEB -eq 1 ]]; then
            if [ $DEBUG -eq 1 ]; then
                echo "check_changed_projects: Both changes found, skipping further checks"
            fi
            return 0
        fi
    done
    return $changed
}


if [ ! -z "$GITHUB_STEP_SUMMARY" ];
then
  echo "## script output" >> "$GITHUB_STEP_SUMMARY"
fi

check_changed_host || check_changed_projects
checkReturnCode=$?
if [ $DEBUG -eq 1 ]; then
    echo "----------"
    echo "Checks returned code: $checkReturnCode"
fi

if [[ $DEPLOY_API -eq 0 ]] && [[ DEPLOY_WEB -eq 0 ]]; then
    if [ $DEBUG -eq 1 ]; then
        echo "no changes detected"
    fi
    if [ ! -z "$GITHUB_STEP_SUMMARY" ];
    then
      echo "No changes detected" >> "$GITHUB_STEP_SUMMARY"
    fi
fi

if [ -z ${GITHUB_ENV+x} ];
then
  echo "DEPLOY_API=$DEPLOY_API"
  echo "DEPLOY_WEB=$DEPLOY_WEB"
else
  if [ $DEBUG -eq 1 ]; then
    echo "writing to GITHUB_OUTPUT -- $GITHUB_OUTPUT"
    echo "DEPLOY_API=$DEPLOY_API"
    echo "DEPLOY_WEB=$DEPLOY_WEB"
  fi
  echo "DEPLOY_API=$DEPLOY_API" >> "$GITHUB_OUTPUT"
  echo "DEPLOY_WEB=$DEPLOY_WEB" >> "$GITHUB_OUTPUT"
  if [ ! -z "$GITHUB_STEP_SUMMARY" ];
  then
    {
      echo "### output variables"
      echo "| Variable   | Value       |"
      echo "| ---------- | ----------- |"
      echo "| DEPLOY_API  | $DEPLOY_API  |"
      echo "| DEPLOY_WEB | $DEPLOY_WEB |"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
fi
