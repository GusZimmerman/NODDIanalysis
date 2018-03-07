#!/bin/sh
#RUGBY_NODDI_pipeline_Freesurfer.sh
#
#SBATCH --job-name=DTIFIT_Freesurfer
#SBATCH --ntasks=1
#
#
#SBATCH --partition=long
#SBATCH --mem=8
#
#-----------------RUGBY DTIFIT Processing steps-------------------
#-----------------Script created by G Zimmerman Oct 2017-----------
#----------------kaz11@imperial.ac.uk-------------------

dcm2niix -z y -o ${1} -f ${1}_%p scans;
#-z y for compression to nii.gz, -o output, -f filename (Subj_Scantype), location of DICOMS.

cp scans/*NODDI_90dir_9b0_multishell*.nii.gz ${1}.nii.gz;
cp scans/*NODDI_90dir_9b0_multishell*.bvec ${1}.bvec;
cp scans/*NODDI_90dir_9b0_multishell*.bval ${1}.bval;
cp scans/*NODDI_b0_reversed.nii.gz P2A_b0.nii.gz;
cp scans/*MPRAGE_ADNI_P2.nii.gz ${1}_T1.nii.gz;

echo create A2P_b0 ${1}
fslroi ${1}.nii.gz A2P_b0 0 1
fslmerge -t A2P_P2A_b0 A2P_b0 P2A_b0
printf "0 -1 0 0.09144\n0 1 0 0.09144\n" > acqparams.txt

echo topup ${1}
topup --imain=A2P_P2A_b0 --datain=acqparams.txt --config=b02b0.cnf --out=my_topup_results --iout=my_hifi_b0

echo fslmaths ${1}
fslmaths my_hifi_b0 -Tmean my_hifi_b0

## Freesurfer ReconAll (creates a skull-stripped brain)
recon-all -subject ${1} -sd /group/tbi/RUGBY/DTI/${1} -i ${1}_T1.nii.gz -all -qcache
#recon-all -subject ${1} -i ${1}_T1.nii.gz -autorecon1
#can add T2 flair?

# Convert from FREESURFER space back to native anatomical space
mri_vol2vol --mov ${1}/mri/brainmask.mgz --targ ${1}/mri/rawavg.mgz --regheader --o ${1}/mri/brainmask-in-rawavg.mgz --no-save-reg

# convert freesurfer mgz output brainmask to nii
mri_convert -ot nii ${1}/mri/brainmask-in-rawavg.mgz ${1}/mri/brainmask.nii.gz

# Register T1 data to NODDI data for the first time, remember filter (duplication)
flirt -in ${1}/mri/brainmask.nii.gz -ref ${1}.nii.gz -out T1toNODDIbrain.nii.gz -omat T1toNODDI.mat -dof 6

# Extracting mask from T1 freesurfer output 
fslmaths T1toNODDIbrain.nii.gz -thr 0 -bin ${1}_mask1.nii.gz

echo creating index
echo `fslinfo ${1}.nii.gz` > numvolumes.txt
vol=`grep -E -o -w "dim4.{0,4}" numvolumes.txt| sed 's/^.* //'`

indx=""
for ((i=1; i<=${vol}; i+=1)); do indx="$indx 1"; done
echo $indx > index.txt

echo eddy correcting ${1}
eddy_openmp --imain=${1}.nii.gz --mask=${1}_mask1.nii.gz --acqp=acqparams.txt --index=index.txt --bvecs=${1}.bvec --bvals=${1}.bval --topup=my_topup_results --repol --out=eddy_corrected_data;

# After eddy, register again T1 to NODDI, should be a better registration
flirt -in ${1}/mri/brainmask.nii.gz -ref eddy_corrected_data.nii.gz -out my_hifi_b0_brain.nii.gz -omat T1toEDDY.mat -dof 6

# After eddy, custom node that extracts mask from T1 freesurfer output
fslmaths my_hifi_b0_brain.nii.gz -thr 0 -bin my_hifi_b0_brain_mask.nii.gz

# MASK eddy output by FINAL T1 BRAIN MASK (T1 registered to eddy corrected NODDI)?
echo dtifit ${1}
dtifit --data=eddy_corrected_data.nii.gz --out=dti --mask=my_hifi_b0_brain_mask --bvecs=eddy_corrected_data.eddy_rotated_bvecs --bvals=${1}.bval -w;

mkdir /group/tbi/RUGBY/NODDI/${1};

echo Extracting post-processing files for ${1}

cp my_hifi_b0_brain_mask.nii.gz /group/tbi/RUGBY/NODDI/${1}/;
cp eddy_corrected_data.nii.gz /group/tbi/RUGBY/NODDI/${1}/NODDI_DWI.nii.gz;
cp ${1}.bval /group/tbi/RUGBY/NODDI/${1}/NODDI_protocol.bval;
cp ${1}.bvec /group/tbi/RUGBY/NODDI/${1}/NODDI_protocol.bvec;
gunzip /group/tbi/RUGBY/NODDI/${1}/my_hifi_b0_brain_mask.nii.gz;
gunzip /group/tbi/RUGBY/NODDI/${1}/NODDI_DWI.nii.gz; 

cd ${cwd};

done
