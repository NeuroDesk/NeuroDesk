#!/usr/bin/env bash
set -e

echo "checking if containers are built"

#creating logfile with available containers
python3 neurodesk/write_log.py
pip3 install requests

# remove empty lines
sed -i '/^$/d' log.txt

# remove square brackets
sed -i 's/[][]//g' log.txt

# remove spaces around
sed -i -e 's/^[ \t]*//' -e 's/[ \t]*$//' log.txt

echo "[debug] logfile:"
cat log.txt
echo "[debug] logfile is at: $PWD"

export IMAGE_HOME="/home/runner"

mapfile -t arr < log.txt
for LINE in "${arr[@]}";
do
    echo "LINE: $LINE"
    export IMAGENAME_BUILDDATE="$(cut -d' ' -f1 <<< ${LINE})"
    echo "IMAGENAME_BUILDDATE: $IMAGENAME_BUILDDATE"

    IMAGENAME="$(cut -d'_' -f1,2 <<< ${IMAGENAME_BUILDDATE})"
    BUILDDATE="$(cut -d'_' -f3 <<< ${IMAGENAME_BUILDDATE})"
    echo "[DEBUG] IMAGENAME: $IMAGENAME"
    echo "[DEBUG] BUILDDATE: $BUILDDATE"

    if curl --output /dev/null --silent --head --fail "https://object-store.rc.nectar.org.au/v1/AUTH_dead991e1fa847e3afcca2d3a7041f5d/neurodesk/${IMAGENAME_BUILDDATE}.simg"; then
        echo "[DEBUG] ${IMAGENAME_BUILDDATE}.simg exists in nectar cloud"
        echo "[DEBUG] refresh timestamp to show it's still in use"
        rclone touch nectar:/neurodesk/${IMAGENAME_BUILDDATE}.simg
    else
        # if image is not in standard nectar cloud then check if the image is in the temporary cache:
        if curl --output /dev/null --silent --head --fail "https://object-store.rc.nectar.org.au/v1/AUTH_dead991e1fa847e3afcca2d3a7041f5d/neurodesk/temporary-builds-new/${IMAGENAME_BUILDDATE}.simg"; then
            # download simg file from cache:
            echo "[DEBUG] ${IMAGENAME_BUILDDATE}.simg exists in temporary cache on nectar cloud"
            curl --output "$IMAGE_HOME/${IMAGENAME_BUILDDATE}.simg" "https://object-store.rc.nectar.org.au/v1/AUTH_dead991e1fa847e3afcca2d3a7041f5d/neurodesk/temporary-builds-new/${IMAGENAME_BUILDDATE}.simg"
            echo "[DEBUG] Deleting file after download or when older than 30days from cache ..."
            rclone delete nectar:/neurodesk/temporary-builds-new/${IMAGENAME_BUILDDATE}.simg
            rclone delete --min-age 30d nectar:/neurodesk/temporary-builds-new
        else
            # image was not released previously and is not in cache - rebuild from docker:
            # check if there is enough free disk space on the runner:
            FREE=`df -k --output=avail "$PWD" | tail -n1`   # df -k not df -h
            echo "[DEBUG] This runner has ${FREE} free disk space"
            if [[ $FREE -lt 20485760 ]]; then               # 20G = 10*1024*1024k
                echo "[DEBUG] This runner has not enough free disk space .. cleaning up!"
                bash .github/workflows/free-up-space.sh
                FREE=`df -k --output=avail "$PWD" | tail -n1`   # df -k not df -h
                echo "[DEBUG] This runner has ${FREE} free disk space after cleanup"
            fi

            if [ -n "$singularity_setup_done" ]; then
                echo "Setup already done. Skipping."
            else
                #install apptainer
                sudo apt update > /dev/null 2>&1
                sudo apt install -y software-properties-common > /dev/null 2>&1
                sudo add-apt-repository -y ppa:apptainer/ppa > /dev/null 2>&1
                sudo apt update > /dev/null 2>&1
                sudo apt install -y apptainer apptainer-suid > /dev/null 2>&1

                export singularity_setup_done="true"
            fi

            echo "[DEBUG] singularity building docker://vnmd/$IMAGENAME:$BUILDDATE"
            singularity build "$IMAGE_HOME/${IMAGENAME_BUILDDATE}.simg"  docker://vnmd/$IMAGENAME:$BUILDDATE
        fi

        echo "[DEBUG] Attempting upload to Nectar Cloud ..."

        rclone copy --progress $IMAGE_HOME/${IMAGENAME_BUILDDATE}.simg nectar:/neurodesk/

        if curl --output /dev/null --silent --head --fail "https://object-store.rc.nectar.org.au/v1/AUTH_dead991e1fa847e3afcca2d3a7041f5d/neurodesk/${IMAGENAME_BUILDDATE}.simg"; then
            echo "[DEBUG] ${IMAGENAME_BUILDDATE}.simg was freshly build and exists now :)"
            echo "[DEBUG] PROCEEDING TO NEXT LINE"
            echo "[DEBUG] Cleaning up ..."
            rm -rf /home/runner/.singularity/docker
            rm -rf $IMAGE_HOME/${IMAGENAME_BUILDDATE}.simg
        else
            echo "[DEBUG] ${IMAGENAME_BUILDDATE}.simg does not exist yet. Something is WRONG"
            exit 2
        fi
    fi 
done < log.txt

# sync the nectar containers to aws-neurocontainers
echo "[Debug] cleanup & syncing nectar containers to aws-neurocontainers"
rclone delete --min-age 30d nectar:/neurodesk/

# Disable sync for now - need to do this with aws cli or find a way of using these credentials in rsync
# check if aws cli is installed
if ! command -v aws &> /dev/null
then
    echo "[DEBUG] Installing AWS CLI"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
fi
rclone sync nectar:/neurodesk/ aws-neurocontainers-new:/neurocontainers/ --checksum --progress

# echo "[Debug] list bucket with aws cli?"
# aws s3 ls s3://neurocontainers/

# echo "[Debug] can we list aws bucket with rclone?"
# rclone ls aws-neurocontainers-new:/neurocontainers/

#once everything is uploaded successfully move log file to cvmfs folder, so cvmfs can start downloading the containers:
echo "[Debug] mv logfile to cvmfs directory"
mv log.txt cvmfs

cd cvmfs
echo "[Debug] generate applist.json file for website"
python json_gen.py #this generates the applist.json for the website
# these files will be committed via uses: stefanzweifel/git-auto-commit-action@v4


# cleanup old containers
# rclone lsl nectar:/neurodesk/temporary-builds-new
# rclone touch nectar:/neurodesk/temporary-builds-new/vesselboost_0.9.4_20240404.simg
# rclone lsl --min-age 7d nectar:/neurodesk/temporary-builds-new
# rclone delete --min-age 7d nectar:/neurodesk/temporary-builds-new

# all current ones:
# rclone lsl --max-age 1d nectar:/neurodesk/

# rclone lsl --min-age 7d nectar:/neurodesk/ --include "*.simg"
# rclone delete --min-age 7d nectar:/neurodesk/ --include "*.simg"
# rclone lsl --min-age 7d nectar:/neurodesk/
# rclone move --min-age 7d nectar:/neurodesk/ nectar:/build/
# rclone lsl --min-age 1d nectar:/neurodesk/
# rclone ls aws-neurocontainers:/neurocontainers/
# rclone ls nectar:/neurodesk/
# rclone sync nectar:/neurodesk/ aws-neurocontainers:/neurocontainers/ --progress
