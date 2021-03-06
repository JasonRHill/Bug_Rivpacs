# R code to build a RIVPACS-type model. ;

# Authored by John Van Sickle, US Environmental Protection Agency, and adapted by Sheila North, Dynamac Corp;

##################################################;

# Set working directory;

#setwd("C:\\Documents and Settings\\Jason\\Desktop\\RIVPACS\\Output")

#load required packages;
library(gtools)
library(MASS);
library(cluster)
library(Hmisc)
library(stats)

############;
# STEP 1 -- INITIAL SETUP -- Input and organize the bug and predictor data;
# The exact code for this step is very particular for each data set, ;
# but similar operations will need to be done on every data set;

###############################;
# Input data are predictor data (all sites) and a (site x taxa) matrix of abundance for all bugs at all sites.;
# The bug matrix is the result of fixed-count subsampling and matrify programs;
# SN: FOR KY/WV INPUT WAS ALL SITES WITH NO TAXA REMOVED A PRIORI;
# Assumes that predictor data file includes a column to identify the calibration, validation and test sites;
# Note: Only include dummy codes for categorical variables with significant coverage 
# For example, drop scarce or unimportant ecoregions from use as a dummy code variable column;

###C is all ref sites, T is all sites outside ref, V is 20% of ref sites/different from C sites
# Step 1a - Read and organize predictor data;

# Input the predictor data, tab delimited. Use the sample/site ID as the row name;
predall<-read.table("C:/Users/ktq89598/Documents/JasonRIVPAC/Bugs2011/predictors_all.txt",row.names="Sample_ID",header=T,sep="\t");

head(predall); #look at 1st 5 rows, all columns;
dim(predall); # number of rows and columns;

#specify candidate predictors;
# First, put the (column) names of candidate predictors in a vector;
candvar<-c("Long","Lat","Julian","logelevation","logcatchment","Precip",
"a69","d69","Slope", "GrpB", "GrpC", "clay", "sand", "Permeability");

## Step 1b - Input the assemblage data (bug data), as a site-by-taxa matrix;

bugall<-read.table("C:/Users/ktq89598/Documents/JasonRIVPAC/Bugs2011/all taxa_all.txt",row.names="Sample_ID",header=T,sep="\t");

## replace NA values with zero values for clustering;
bugall[ is.na(bugall) ] <- 0

## Step 1c - Align bug and predictor data, by site/sample;
#check sample(row) alignment of bug and predictor data;
row.names(bugall)==row.names(predall);
# NB: If samples are not aligned, fix by aligning bugs data to predictor data, since latter is sorted by sample type;
# bugall<-bugall[row.names(predall),];
#check alignment again -- alignment OK;
# row.names(bugall)==row.names(predall);

### Step 1d - Create subsets of calibration and validation data;

#First, create a Presence/absence (1/0) matrix (site by taxa) for the bugs;
bugall.pa<-bugall;
bugall.pa[bugall.pa>0]<-1;

# Extract subsets of bug and predictor data for the calibration ("C") and validation ("V") sites;
predcal<-predall[predall[,'set']=='C',];  #predictor data -calibration sites;
pred.vld<-predall[predall[,'set']=='V',];  #predictor data - validation sites;

bugcal<-bugall[predall[,'set']=='C',]; #Bug Abundance matrix, calibration sites;
bugcal.pa.all<-bugall.pa[predall[,'set']=='C',]; #Bug presence/absence matrix, calibration sites;
bug.vld.pa.all<-bugall.pa[predall[,'set']=='V',]; #Bug presence/absence matrix, validation sites;

#First, get a vector containing the proportion of calibration sites  at which each taxon occurs;
psite.occ<-colSums(bugcal.pa.all)/dim(bugcal.pa.all)[[1]];

#Now get a vector of names of taxa occuring at greater than 0% of calibration sites;
#want to use only these taxa in O/E;
calnames<-names(bugcal.pa.all)[psite.occ>0]; 
bugcal.pa<- bugcal.pa.all[,calnames];
bug.vld.pa<-bug.vld.pa.all[,calnames];

#Data sets complete and aligned;
 ########################################;

#STEP 2 -- DISSIMILARITIES AND CLUSTER ANALYSIS;

# Prepare the bug matrix to be used in calculating site dissimilarities for clustering;

# compute dissimilarity matrix for calibration site bugs;
# at this stage, have not excluded any rare taxa;
# The code below calculates Bray-Curtis (Sorenson) dissimilarities for relative abundance data; 
# Code for using Jaccard (P/A data) and Sorenson (P/A data) dissimilarity is also available in v4.1;
# Other sources for dissimilarities include vegdist() in vegan package (BC, Jaccard, and others);
#Also, gdist() in package mvpart, and dist() in base R;

#To cluster based on P/A matrix, first remove rare taxa;

#vector of names of taxa occuring at greater than 5% of calibration sites;
#want to use only these taxa in clustering;
#nonrare.taxa<-names(psite.occ)[psite.occ>0.05]; 
#Now subset the site-by-taxa matrix to create a new one containing only the nonrare taxa;
#PA.matrix.for.clustering<- bugcal.pa[,nonrare.taxa];
#Then use PA.matrix.for.clustering in the Jaccard or Sorenson functions;

#Another option is to cluster based on a relative abundance matrix;
#In this example, produce untransformed relative abundance;
#first compute site by spp matrix of relative abundance;
totabun<-apply(bugcal,1,sum); #vector of total abundance, each site;
rel.abun<-sweep(bugcal,1,totabun,FUN="/"); #relative abundance matrix;
#Now use rel.abun matrix in the Bray-Curtis dissimilarity function;

# Here, I use the generalized outer product function dapply();
# and choose the desired dissimilarity measure as a called function;
# dapply() output is an (n(n-1)/2) length vector storing ;
# the lower triangle of the site dissimilarity matrix in column major order;
# can be input directly to R clustering functions;

#Load the dapply function;

source("C:/Users/ktq89598/Documents/JasonRIVPAC/Bugs2011/dapply.r");

# Function below computes Bray-Curtis(Sorenson) dissim within dapply();
# Instead, could use gdist() in mvpart package, to do Bray-Curtis;
#siti, sitj are vectors of abundances for 2 sites;
#if zero abundance at both sites, then dissimilarity=0;

   bcfun<-function(siti,sitj) {
          bcnum<-sum(abs(siti-sitj));
          bcdenom<-sum(siti+sitj);
          ifelse(bcdenom>0, (bcnum/bcdenom),0); #return BC dissimilarity;
                } #end of function;

#compute Bray-Curtis dissimilarity;
dissim<-dapply(rel.abun,1,rel.abun,1,bcfun);
#Proceed to clustering;
#########################;
####################################;
# Clustering of calibration sites;
# Used flexible-Beta method, with Beta=-0.3;
#See R documentation on agnes() in "cluster" package;
# When using agnes() with Flexible Beta strategy, set Beta=(1-2*Alpha) in Lance-Williams formula;
#A single value for par.method value specifies alpha, so alpha=0.65 gives Beta=-0.3;

clus1<-agnes(x=dissim,diss=T,method="flexible", par.method=0.65,keep.diss=F,keep.data=F);
save(clus1,file="myclus1.Rdata");

## Various plots of cluster outcome. Leaf labels are row numbers of dissim matrix;
#that is, the order of sites in the calibration data set;
#plot the dendrogram;
plot(clus1,which.plots=2,labels=row.names(bugcal),cex=.4);


#######################;
#Pruning the dendrogram to create a small number of groups;
# level pruning can be done by specifying the number of groups (k parameter);
#Also can prune at a specified height. See cutree help;
#result is a vector of site group assignments;
#can repeat this process to generate several candidate groupings from a single dendrogram;

# First example is "level" pruning to afixed number of groups;
###So make sure to look at your graph to decide number of ref site grouping!
grps.4<-cutree(clus1,k=4); #vector of group assignments is in the order of sites in the clustered data;
table(grps.4); #count number of sites in each group;
grp <- cbind(row.names(predcal),grps.4); #list calibration sites and their group assignments;
#candidate site groups complete;

write.csv(grp,file='grp4.csv');


#####################################;

#STEP 3 -- DISCRIMINANT FUNCTION ANALYSIS (DFA);

# Note - Instead of DFA, consider using classification tree model (R packages "tree" or "rpart");
#  or a random forest model (R package "randomForest"):

#Below, I have options for stepwise DFA and also for all-subsets DFA;

########################################;

 ###########################;
 # Option 1 -- Stepwise DFA;
 
#Load the step.dfa function;
# source("dfa.step.r");

#then execute one of the two below. First is forward stepwise, second is backwards stepwise;
# See dfa.step documentation. Step.res contains the final chosen model as an lda() object;

# step.res<-dfa.step(predcal=predcal,candvar=candvar,grps=grps.6, P.stay.lim=.051,P.enter.lim=.05);
#or could do backwards stepwise;
# step.res<-dfa.step(predcal=predcal,candvar=candvar,method='backward',grps=grps.6P.stay.lim=.051,P.enter.lim=.05);


#Option 2 -- All subsets DFA; 

# Feasible for up to about 15 candidate predictors;
# User specifies a small number of best models for selected model orders;
# Wilks lambda, classification accuracy, and statistics of O/E are reported for each best model;
# If user supplies an independent set of validation data (bug data and predictor data), then;
# O/E statistics also computed for validation set;
# In addition (version 4), the CV confusion matrices are reported for each of the best models;
#Also, the null model statistics are available;

#specify a vector describing how many models of each order to keep; 
# The following example is for a case with 9 candidate predictors;
# For example, keep 8 models each for orders 1,2, ...13,
# and also keep the single (saturated) model of order 14,
###If you have 15+ predictor values, this call is reasonable place to retain the top models
 nkeep<-c(rep(8,13),1);

#Load the all subsets DFA function;
source("C:/Users/ktq89598/Documents/JasonRIVPAC/Bugs2011/dfa.allsub.v4.r");

#execute the following block of code. dfa.allsub.v3() is surrounded;
#by code that records and prints the execution time;
#Execution may take several minutes;

#In example below, Pc is set to 0.5.
#To retain all taxa in O/E, set Pc to a very small number, like 1.e-14.

start.time=proc.time();
dfm.best<-dfa.allsub.v3(bug.cal=bugcal.pa,bug.vld=bug.vld.pa,pred.cal=predcal,pred.vld=pred.vld,
                    grps=grps.4,candvar=candvar,numkeep=nkeep,Pc=0.5);
elaps<-proc.time()-start.time;
print(c("elapsed time = ",elaps));
                                                   
dfm.best.5grp.0<-dfm.best; #Can store result under a new name, indicating the Pc value used;
dfm.best.5grp.5<-dfm.best; # Can store result of a second run, which had Pc=0.5;

#################;

# Various ideas for exploring the subset of "best" DFA models produced by dfa.allsub;
# dfa.allsub yields a list containing the statistics of O/E: a) predicted by the null model (null.stats),
 #  and b) predicted by several "best" predictive models (subset.stats); 

###JRH take a look at SDOE.cal needs to be less the 0.20 to be good andMNOE.cal (close to 1!)
  
 #A) Performance of the null model;
 dfm.best$null.stats; 
 
# B)Performance of subsets of best predictive models;
bestmods<-dfm.best$subset.stats;
head(bestmods);
#look at model #20;
bestmods[20,];
#look at all best models, sorted by SD(O/E) at CAL sites;
format(bestmods[order(bestmods$SDOE.cal),],digits=3);

# C) Look at crossvalidated error matrix of a selected best model;
dfm.best$CV.error.matrices[20]; #For model #20;


# D) plot a measure of model performance against model size (ie, model order);
    #For example, plot RMSE(O/E) against model order separately for calibration and validation sites;
 par(mfrow=c(1,1));
plot(bestmods$order,bestmods$RMSE.cal,ylim=c(0.15,0.35),type='p',pch='C', col='blue',
      cex=.7,xlab='Model order',ylab='RMSE(O/E)');
points(bestmods$order,bestmods$RMSE.vld,pch='V',cex=.7,col='red');

#The following lines put a title and legend on the plot;
legend(locator(1),legend=c('Calibration sites','Validation sites'),pch=c('C','V'));
title(main=list('Central Appalachian Ecoregion models: Five best of each order',cex=.9));

#put null model RMSE as a baseline, separate for Calibration and validation sites.;
abline(dfm.best$null.stats["RMSE.cal"],0,lty=1);
abline(dfm.best$null.stats["RMSE.vld"],0,lty=2);


#Can also experiment with similar plots for BC statistics. "Better" models will have;
# smaller BC90;

###;
# E) Plot the two classification accuracy measures against model order;
 # DFM overfitting starts occurring where the CV accuracy flattens out;
 plot(bestmods$order,bestmods$cls.crct.resub,ylim=c(20,85),type='p',pch='R',
      cex=.5,xlab='Model order',ylab='Percent correct');
points(bestmods$order,bestmods$cls.crct.cv,pch='C',cex=.5);
legend(locator(1),legend=c('Resubstitution','Crossvalidation'),pch=c('R','C'));
title(main=list('Central Appalachian models: Model classification accuracy: Five best of each order',cex=.9));


#F) PREDICTOR IMPORTANCE. Calculate the percentage of best models that include;
# each of the predictors. Percentage is not weighted by model quality;
####the number of models this is included in, Julian day, lat, precip, long
 round((100*table(unlist(strsplit(bestmods$model," ")))/dim(bestmods)[[1]]),1);

#G) scatterplot matrix of model size and performance on validation and calibration sites;
pairs(as.matrix(bestmods[,c('order','RMSE.cal','RMSE.vld')]));

##########;

##  Step 3.5 - Based on the stepwise or all-subsets DFA, or on other evaluations, declare your choice of the 
#predictors that will be used in the final model;
#Define the vector "preds.final" to contain the names of the final, chosen predictor variables;

#Option 1 - Choose final predictors from the output of all-subsets run;
  #Option 1A - Choose the predictors from the interactive identification;
   # preds.final<-unlist(strsplit(bestmods[cc,'model']," "));
  #Option 1B choose predictors from a specific row in bestmods data frame;
   # preds.final<-unlist(strsplit(bestmods[13,'model']," "));

#Option 2 - Choose the final model from stepwise DFA run, which is stored in step.res;
# preds.final<-attr(terms(step.res),"term.labels");

# OPTION 3 -- Directly specify the names of chosen predictors;
preds.final<-c("a69","Julian", "Lat");

#############################################################;

#STEP 4 - Finalize calculations of final, chosen predictive model;
# To specify the entire final model, you need to store/export 5 things:
# 4.1) The site-by-taxa matrix of observed presence/absence at calibration sites (bugcal.pa, already available);
# 4.2) Specify the vector of final group membership assignments at calibration sites(grps.final);
      grps.final<-grps.4;
# 4.3) Specify the final selected predictor variables (preds.final) - already done in step 3.5;
# 4.4) Calculate the matrix(grpmns) of mean values of the preds.final variables for the final calibration site groups ;
     datmat<-as.matrix(predcal[,preds.final])
     grpmns<-apply(datmat,2,function(x)tapply(x,grps.final,mean));
# 4.5) The inverse pooled covariance matrix(covpinv) of the preds.final variables at the calibration sites;
     #First, calculate a list of covariance matrices for each group;
      covlist<-lapply(split.data.frame(datmat,grps.final),cov);
      #pooled cov matrix is a weighted average of group matrices, weighted by group size;
      grpsiz<-table(grps.final);
      ngrps<-length(grpsiz);
      npreds<-length(preds.final);
     #zero out an initial matrix for pooled covariance;
     covpool<-matrix(rep(0,npreds*npreds),nrow=npreds,dimnames=dimnames(covlist[[1]]));
     #weighted sum of covariance matrices;
     for(i in 1:ngrps){covpool<-covpool+(grpsiz[i]-1)*covlist[[i]]};
     covpool<-covpool/(sum(grpsiz)-ngrps);#renormalize;
     covpinv<-solve(covpool); #inverse of pooled cov matrix;

     
     ###make a prednew and bugnew for model.predict.v4.1??? Apparently yes! JRH
     prednew <- predcal
     bugnew <- bugcal.pa
#################################;

#Step 5 - Further checks on performance of the final, chosen model;

#Option 5.1 - Make predictions of E and O/E for calibration (reference) sites. Examine O/E statistics and plots;
  # To do this, run the model.predict function, using the calibration data as the 'new' data;
  # See Step 7 below, for more info on making predictions, and also see internal documentation of model.predict.v4;
     
  source("C:/Users/ktq89598/Documents/JasonRIVPAC/Bugs2011/model.predict.v4.1.r");
  #OE.assess.cal<<-model.predict.v4.1(bugcal.pa,grps.final,preds.final,grpmns,covpinv,prednew=predcal,bugnew.pa=bugcal.pa,Pc=0.5);
  OE.assess.cal<<-model.predict.v4.1(bugcal.pa,grps.final,preds.final,grpmns,covpinv,prednew,bugnew,Pc=0.5);
# function prints out mean and SD of O/E, in this case, for the calibration sites;
# If an all-subsets model was selected, then these stats
# should match the values given in dfm.best$bestmods, for the selected model;

# Write scores to csv file for export (SN 8/12);
write.csv(OE.assess.cal,file='oe_cal.csv');

# Write Pc values per taxon/site to csv file for export (SN 8/20);
write.csv(OE.assess.cal$Capture.Probs, file='pc_cal.csv');

#look at other prediction results, for calibration sites;
  names(OE.assess.cal);   #names of 2 components of the prediction results list;
  head(OE.assess.cal$OE.scores); #data frame of O/E scores, 1st 5 rows;
  head(OE.assess.cal$Capture.Probs); #predicted capture probabilties;
#check distribution of Calibration-site O/E scores. Is it Normal?;
#plot a histogram and a Normal q-q plot;
par(mfrow=c(3,1));
hist(OE.assess.cal$OE.scores$OoverE,xlab="O/E");
qqnorm(OE.assess.cal$OE.scores$OoverE);

#scatterplot of O (on y-axis) vs E (on x-axis). See Pineiro et al. Ecol. Modelling 2008, 316-322, for this choice of axes;
  plot(OE.assess.cal$OE.scores[,c('E','O')],xlab='Expected richness',ylab='Observed richness',xlim=c(0,25),ylim=c(0,25));
  abline(0,1); #add a 1-1 line;

###########;

     ###JRH, try just using second half of call to run model function, it works uses the variable just fine with a different
     ###name in the function
     
### Option 5.2 - Repeat Step 5.1, but this time use validation data. Check especially for model bias (mean(O/E) differs from 1.0);
   #OE.assess.vld<-model.predict.v4.1(bugcal.pa,grps.final,preds.final, grpmns,covpinv,prednew=pred.vld,bugnew.pa=bug.vld.pa,Pc=0.5)  ;
     OE.assess.vld<-model.predict.v4.1(bugcal.pa,grps.final,preds.final,grpmns,covpinv,pred.vld,bug.vld.pa,Pc=0.5)  ;
     OE.assess.vld$OE.scores;
  #Can repeat predictions for a different Pc cutoff;
  # This example is for a cutoff of 0 (include all taxa). Need to use a very small positive number for Pc parameter;
  # OE.assess.vld.alltax<-model.predict.v4.1(bugcal.pa,grps.final,preds.final, grpmns,covpinv,prednew=pred.vld,bugnew.pa=bug.vld.pa,Pc=0.5)  ;
     OE.assess.vld.alltax<-model.predict.v4.1(bugcal.pa,grps.final,preds.final,grpmns,covpinv,pred.vld,bug.vld.pa,Pc=0.000005)  ;
     OE.assess.vld.alltax$OE.scores;

# Write scores to csv file for export (SN 8/12);
write.csv(OE.assess.vld$OE.scores,file='oe_val.csv');

# Write Pc values per taxon/site to csv file for export (SN 8/20);
write.csv(OE.assess.vld$Capture.Probs, file='pc_vld.csv');

 #################################;
#Step 6 -- Save/export the final model for use by others;

    #Option 6.1 - Save the model components together in a single .Rdata file.;
    # Any R user can load this file, along with model.predict.v4.r, to make predictions from the model;
    # See Step 7 below;
      save(bugcal.pa, predcal, grps.final, preds.final, grpmns, covpinv,file='R3Model3Var.Version1.Rdata');
    #NOTE - Predcal is not needed to define the model, but is included so that users see the required format for predictor data;

#Option 6.2 - Export the final model pieces as tab-delimited text files, in the formats needed for uploading to WCEM website;

################################;

# Step 7 - Making predictions for test sites and new data.

# first, source the prediction script and also load the desired model;
   source("C:/Users/ktq89598/Documents/JasonRIVPAC/Bugs2011/model.predict.v4.1.r");
   load('R3Model3Var.Version1.Rdata');

# User must supply a sample-by-taxa matrix of taxa presence/absence (coded as 1 or 0), for all new samples;
   # User must also supply a corresponding file of predictor data for those same samples;
   # These 2 files should have similar formats as the original taxa and predictor data sets used to build the model (see step 1 above);
   # Notes on file formats --
   #   A) The sample ID column in both files should be read into R as a row name (see Step 1 examples).
   #   B) Predictor data set -- Must include columns with the same names, units, etc.,
   #        as the model's predictor variables. All other columns will be ignored;
   #        Column order does not matter;
   #        Predictions and calculations of O/E will be made only for those samples that have;
   #        complete data for all model predictors.;
   #   ###JRH Question....did greg pond us presence/abssence or abundance?!?
   #   C)  Sample-by-taxa matrix. Can contain abundance or presence/absence (1 or 0). Missing or empty cells now allowed;
   #       Sample ID's (row names) must match those of predictor data.
   #       Any names for new taxa (column names) are acceptable, in any order;
   #       HOWEVER - Only those new-data taxa names that match the names in the
   #            calibration data can be use to calculate observed richness;
   #            All other taxa (columns) in the new-data bug matrix are ignored;
   #        To see a list of the calibration-taxa names, do:
            names(bugcal.pa)[colSums(bugcal.pa)>0];

##########;

# Example predictions;

pred.test<-predall[predall[,'set']=='T',]; #predictor data - test sites;
bug.test<-bugall.pa[predall[,'set']=='T',]; #Bug Abundance matrix, calibration sites;

#Drop all samples/sites that do not not have complete data for the model predictors;
pred.test<-pred.test[complete.cases(pred.test[,preds.final]),];
bug.test<-bug.test[row.names(pred.test),];

#makes predictions for test data;
OE.assess.test<-model.predict.v4.1(bugcal.pa,grps.final,preds.final, grpmns,covpinv,prednew=pred.test,bugnew=bug.test,Pc=0.5);

# look at O/E scores, for all samples;
 OE.assess.test$OE.scores;


# Write scores to csv file for export (SN 8/12);
write.csv(OE.assess.test$OE.scores,file='oe_test.csv');

# Write Pc values per taxon/site to csv file for export (SN 8/20);
write.csv(OE.assess.test$Capture.Probs, file='pc_test.csv');

################ ;
######JRH ok its now running, need to create for fish! talk to greg about presense/abs - okay so just presense/abs to run after you have the model
     
     
     
## Input the [new/test] EPA site assemblage data (bug data), as a site-by-taxa matrix;

bug.epa<-read.table("C:\\Documents and Settings\\Jason\\Desktop\\RIVPACS\\Data files\\epatest_taxa_all.txt",row.names="Sample_ID",header=T,sep="\t");

## replace NA values with zero values;
bug.epa[ is.na(bug.epa) ] <- 0

# Create a Presence/absence (1/0) matrix (site by taxa) for the bugs;

bug.epa.pa<-bug.epa;
bug.epa.pa[bug.epa.pa>0]<-1;

head(bug.epa.pa); #look at 1st 5 rows, all columns;
dim(bug.epa.pa); # number of rows and columns;

# User must also supply a corresponding file of predictor data for those same samples;

pred.epa<-read.table("C:\\Documents and Settings\\Jason\\Desktop\\RIVPACS\\Data files\\epatest_predictors.txt",row.names="Sample_ID",header=T,sep="\t");

head(pred.epa); #look at 1st 5 rows, all columns;
dim(pred.epa); # number of rows and columns;

##########;

#makes predictions for [new/test] EPA samples;

OE.assess.epa<-model.predict.v4.1(bugcal.pa,grps.final,preds.final,grpmns,covpinv,prednew=pred.epa,bugnew=bug.epa.pa,Pc=0.5);

# look at O/E scores, for all samples;
 OE.assess.epa$OE.scores;

# Write scores to csv file for export (SN 8/12);
write.csv(OE.assess.epa$OE.scores,file='oe_epa.csv');


# Write scores to csv file for export (SN 8/12);
write.csv(OE.assess.epa$OE.scores,file='oe_epa.csv');

# Write Pc values per taxon/site to csv file for export (SN 8/20);
write.csv(OE.assess.epa$Capture.Probs, file='pc_epa.csv')











