#!/bin/bash -i

# fetch_and_run.sh [name] [version] [date] {cmd} {args}
# Example:
#   fetch_and_run.sh itksnap 3.8.0 20200505 itksnap-wt

# source ~/.bashrc
_script="$(readlink -f "${BASH_SOURCE[0]}")" ## who am i? ##
_base="$(dirname "$_script")" ## Delete last component from $_script ##
echo "[DEBUG] fetch_and_run.sh: Script name : $_script"
echo "[DEBUG] fetch_and_run.sh: Current working dir : $PWD"
echo "[DEBUG] fetch_and_run.sh: Script location path (dir) : $_base"
echo "[DEBUG] fetch_and_run.sh: SINGULARITY_BINDPATH : $SINGULARITY_BINDPATH"

# -z checks if SINGULARITY_BINDPATH is not set
if [ -z "$SINGULARITY_BINDPATH" ]
then
      echo "[DEBUG] fetch_and_run.sh: SINGULARITY_BINDPATH is not set. Trying to set it"
      `cat /etc/bash.bashrc | grep SINGULARITY_BINDPATH`
fi

# shellcheck disable=SC1091
source "${_base}"/configparser.sh "${_base}"/config.ini

MOD_NAME=$1
MOD_VERS=$2
MOD_DATE=$3
IMG_NAME=${MOD_NAME}_${MOD_VERS}_${MOD_DATE}

# -z checks if a CVMFS_DISABLE is NOT set
if [ -z "$CVMFS_DISABLE" ]; then
    if [[ -f "/cvmfs/neurodesk.ardc.edu.au/containers/$IMG_NAME/commands.txt" ]]; then
        echo "CVMFS detected and Container seems to be available"
    else
        echo "CVMFS does not seem to work or is disabled or the container is not available."
        CVMFS_DISABLE=true
    fi
fi

# -z checks if a variable is NOT set
if [ -z "$CVMFS_DISABLE" ]; then
        echo "Mounting containers from CVMFS directly."
        CONTAINER_PATH=/cvmfs/neurodesk.ardc.edu.au/containers
        MODS_PATH=$CONTAINER_PATH/modules
        module use ${MODS_PATH}
else
        echo "Not using CVMFS! Downloading containers fully!"
        # shellcheck disable=SC1091
        source "${_base}"/fetch_containers.sh "$1" "$2" "$3"
        CONTAINER_PATH="${_base}"/containers
fi


echo "[DEBUG] fetch_and_run.sh: fetching containers done."
echo "[DEBUG] fetch_and_run.sh: MOD_NAME: " "$MOD_NAME"
echo "[DEBUG] fetch_and_run.sh: MOD_VERS: " "$MOD_VERS"


echo "[DEBUG] fetch_and_run.sh: Module '${MOD_NAME}/${MOD_VERS}' is installed. Use the command 'module load ${MOD_NAME}/${MOD_VERS}' outside of this shell to use it."

# If no additional command -> Give user a shell in the image after loading the module to set SINGULARITY/APPTAINER_BINDPATH
if [ $# -le 3 ]; then
    CONTAINER_FILE_NAME=${CONTAINER_PATH}/${IMG_NAME}/${IMG_NAME}.simg
    echo "[DEBUG] fetch_and_run.sh: looking for ${CONTAINER_FILE_NAME}"
    if [ -e "${CONTAINER_FILE_NAME}" ]; then
        cd 
        echo "[DEBUG] fetch_and_run.sh: Module loading the container to set environment variables."
        module load "${MOD_NAME}"/"${MOD_VERS}"
        echo "[DEBUG] fetch_and_run.sh: Attempting to launch container ${IMG_NAME}"
        
        export SINGULARITYENV_PS1="${MOD_NAME}-${MOD_VERS}:\w$ "
        # shellcheck disable=SC2154
        singularity --silent exec  "${neurodesk_singularity_opts}" "${CONTAINER_FILE_NAME}" cat /README.md
        singularity --silent shell  "${neurodesk_singularity_opts}" "${CONTAINER_FILE_NAME}"
        if [ $? -eq 0 ]; then
            echo "[DEBUG] fetch_and_run.sh: Container ran OK"
        else
            echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
            echo "the container ${CONTAINER_FILE_NAME} experienced an error when starting. This could be a problem with your firewall if it uses deep packet inspection. Please ask your IT if they do this and what they are blocking."
            echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
            
            read -n 1 -s -r -p "Press any key to continue..."
            
            echo "downloading the complete container as a workaround ..."
            # shellcheck disable=SC1091
            source "${_base}"/fetch_containers.sh "$1" "$2" "$3"
            CONTAINER_PATH="${_base}"/containers
            CONTAINER_FILE_NAME=${CONTAINER_PATH}/${IMG_NAME}/${IMG_NAME}.simg
            singularity --silent exec  "${neurodesk_singularity_opts}" "${CONTAINER_FILE_NAME}" cat /README.md
            singularity --silent shell  "${neurodesk_singularity_opts}" "${CONTAINER_FILE_NAME}"
            if [ $? -eq 0 ]; then
                echo "[DEBUG] fetch_and_run.sh: Container ran OK"
            else
                echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
                echo "the container ${CONTAINER_FILE_NAME} doesn't exist. There is something wrong with the container download. Please ask for help here with the output of this window: https://github.com/orgs/NeuroDesk/discussions "
                echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
                read -n 1 -s -r -p "Press any key to continue..."
            fi
        fi
    else 
        echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        echo "the container ${CONTAINER_FILE_NAME} doesn't exist. There is something wrong with the container download or CVMFS. Please ask for help here with the output of this window: https://github.com/orgs/NeuroDesk/discussions "
        echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        read -n 1 -s -r -p "Press any key to continue..."
    fi
fi

# If additional command -> Run it via module system
echo "[DEBUG] fetch_and_run.sh: module load ${MOD_NAME}/${MOD_VERS}"
module load ${MOD_NAME}/${MOD_VERS}
echo "[DEBUG] fetch_and_run.sh: Running command '${@:4}'."
${@:4}
