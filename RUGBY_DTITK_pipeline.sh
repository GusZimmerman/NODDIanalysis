#!/bin/sh

#------------------------DTITK processing pipeline----------------------
#--------Written by A Jolly, 2016, Edited by Gus Zimmerman, 2017--------
#-----------------------amy.jolly@imperial.ac.uk------------------------

echo "Beginning DTITK pipeline"
module load fsl/5.0.10
module load mricroGL

subj=`cat subjects.txt`
cwd=`pwd`

echo "Adding dtitk to user environment"

export DTITK_ROOT=/apps/software/dtitk/2.3.1/
export PATH=$PATH:$DTITK_ROOT/bin:$DTITK_ROOT/utilities:$DTITK_ROOT/scripts:$DTITK_ROOT/lib:$DTITK_ROOT/include

echo "Creating dtitk files"

mkdir ./DTITK

for f in ${subj};do
fsl_to_dtitk ${f}/dti;
cp ${f}/dti_dtitk.nii.gz DTITK/${f}_dtitk.nii.gz;done

echo "Making DTITK directory and copying files over"

cd DTITK/;
for i in *_dtitk.nii.gz;do 
echo ${i};done>DTI_subjs.txt;

cp /group/tbi/ERANET/Scripts/MedLegal_Tracts_DTITK/* .

echo "Bootstrapping data"

export DTITK_ROOT=/apps/software/dtitk/2.3.1/
export PATH=$PATH:$DTITK_ROOT/bin:$DTITK_ROOT/utilities:$DTITK_ROOT/scripts:$DTITK_ROOT/lib:$DTITK_ROOT/include

dti_template_bootstrap ixi_aging_template.nii.gz DTI_subjs.txt;

echo "Complete-now performing rigid registration"

dti_rigid_population mean_initial.nii.gz DTI_subjs.txt EDS 3;

echo "Complete-now performing affine registration"

dti_affine_population mean_initial.nii.gz DTI_subjs.txt EDS 3;

echo "Complete"

TVtool -in mean_affine3.nii.gz -tr;

echo "Creating mask for diffeomorphic registration"

BinaryThresholdImageFilter mean_affine3_tr.nii.gz mask.nii.gz 0.01 100 1 0;

echo "Running Diffeomorphic registration"

dti_diffeomorphic_population mean_affine3.nii.gz DTI_subjs_aff.txt mask.nii.gz 0.002;

echo "Complete"

echo "Making images 1mm isotropic" 

dti_warp_to_template_group DTI_subjs.txt mean_diffeomorphic_initial6.nii.gz 1 1 1;

echo "Combining the affine and diffeomorphic registrations"

for f in *_dtitk.nii.gz;do echo ${f/.nii.gz/};done>DTI_subjects_combined.txt;

for f in `cat DTI_subjects_combined.txt`;do dfRightComposeAffine -aff ${f}.aff -df ${f}_aff_diffeo.df.nii.gz -out ${f}_combined.df.nii.gz;done

echo "Rigid registration to IITmeantensor256-MNI space"

dti_rigid_reg IITmean_tensor_256.nii mean_diffeomorphic_initial6.nii.gz EDS 4 4 4 0.001;

echo "Affine registration to IITmeantensor256"

dti_affine_reg IITmean_tensor_256.nii mean_diffeomorphic_initial6.nii.gz EDS 4 4 4 0.001 1;

echo "Diffeomorphic registration to IITmeantensor 256"

dti_diffeomorphic_reg IITmean_tensor_256.nii mean_diffeomorphic_initial6_aff.nii.gz IITmean_tensor_mask_256.nii.gz 1 6 0.002;

dfRightComposeAffine -aff mean_diffeomorphic_initial6.aff -df mean_diffeomorphic_initial6_aff_diffeo.df.nii.gz -out mean_combined.df.nii.gz;


echo "Transforming subjects from native to standard space"

for f in `cat DTI_subjects_combined.txt`;do dfComposition -df2 ${f}_combined.df.nii.gz -df1 mean_combined.df.nii.gz -out ${f}_to_standard.df.nii.gz;done;

for f in `cat DTI_subjects_combined.txt`;do deformationSymTensor3DVolume -in ${f}.nii.gz -trans ${f}_to_standard.df.nii.gz -target IITmean_tensor_256.nii -out ${f}_to_standard.nii.gz;done;

echo "Creating 4d file of all subjects registrations to standard space for QC"

fslmerge -t all_subjs_to_standard_tensor.nii.gz *_to_standard.nii.gz;

echo "Creating mean tensor image for subjects"

for f in *_to_standard.nii.gz;do echo ${f};done>DTI_subjs_normalised256.txt;

TVMean -in DTI_subjs_normalised256.txt -out mean_final_high_res.nii.gz;

echo "Creating mean FA image for all subjects"

TVtool -in mean_final_high_res.nii.gz -fa;

cp mean_final_high_res_fa.nii.gz mean_FA.nii.gz;

tbss_skeleton -i mean_FA.nii.gz -o mean_FA_skeleton;

echo "Creating individuals FA maps normalised to standard space"

for f in `cat DTI_subjs_normalised256.txt`;do TVtool -in ${f} -fa;TVtool -in ${f} -tr;done;

echo "Creating MD maps normalised to standard space"

for f in `cat DTI_subjs_normalised256.txt`; do MDsubj=${f%_to_standard.nii.gz}; fslmaths ${MDsubj}_to_standard_tr.nii.gz -div 3 ${MDsubj}_to_standard_md.nii.gz;done;

fslmerge -t all_FA.nii.gz *_to_standard_fa.nii.gz;

echo "Creating TBSS directories for TBSS prcoessing step 4 and statistics"

mkdir TBSS;

mkdir TBSS/FA;

mkdir TBSS/stats;

cp IITmean_tensor_256.nii TBSS/FA/target.nii.gz;

cp all_FA.nii.gz TBSS/stats/;
cp mean_FA* TBSS/stats/;

fslmaths all_FA -max 0 -Tmin -bin mean_FA_mask -odt char;

cp mean_FA_mask.nii.gz TBSS/stats/;

cd TBSS/;

tbss_4_prestats 0.2;

echo "Done-Ready for TBSS or signle subject statistics"

done


