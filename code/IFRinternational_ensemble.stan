functions {
  
  // function to sum across groups
  real[] alignSUM(real[] d, int Nage, int[] AMin, int[] AMax){
    
    real Da[Nage];
    for(a in 1:Nage) Da[a] = sum(d[AMin[a]:AMax[a]]);
    return(Da);
  }
  
  // function to average across groups
  real[] alignMEAN(real[] d, int Nage, int[] AMin, int[] AMax){
    
    real Da[Nage];
    for(a in 1:Nage) Da[a] = mean(d[AMin[a]:AMax[a]]);
    return(Da);
  }
}



data {
   
  // Number of areas, age-groups & gender by area
  int <lower=1> NArea; 
  int <lower=1> NAges[NArea];
  int gender[NArea]; 
  
  // Population by 5 year age groups
  matrix[17,NArea] pop_m;
  matrix[17,NArea] pop_f;
  int pop_b[17,NArea];
  
  // Age-specific death data <65 years
  int deaths_m[13,NArea];
  int deaths_f[13,NArea];
  int deaths_b[13,NArea];
  
  // Min & max of age bands for indexing
  int ageG_min[13,NArea];
  int ageG_max[13,NArea];
  
  // Adjusted death data 65+ (i.e. non-LTC deaths)
  int deaths65p_m[4];
  int deaths65p_f[4];
  int indexArea65p;

  // Age-specific relative probabilities of infection
  real relProbInfection[17];
  
  // Serology data
  int NSero;
  int SeroAreaIndex[NSero];
  int NSamples[NSero];
  int NPos[NSero];
  int tmin[NSero];
  int tmax[NSero];
  real seroprev[NSero];
 
  // Time series of deaths
  int Ndays;
  int deathsTinfec[Ndays,NArea];
  int deathsTsero[Ndays,NArea];
  int deathsT[Ndays+10,NArea];
  int TdeathsA[NArea];

}

parameters {
  
  real <lower=-50, upper=1> log_probInfec[NArea];  
  real <lower=-50, upper=-0.001> log_ifr_m[13];
  real <lower=-50, upper=-0.001> log_ifr_f[13];
  real <lower=0> V;
}

transformed parameters {
  
  // cumulative prob infection
  real probInfec[NArea];

  // estimated deaths by age, sex & area
  real natDeath_m[17,NArea];
  real natDeath_f[17,NArea];
  real natDeath_b[17,NArea];
  
  // time series of infections & seroprevalence
  matrix[Ndays,NArea] seroT;
  matrix[Ndays,NArea] infecT;
  
  // total deaths <65 and 65+
  real u65deaths[NArea];
  real o65deaths[NArea];
  
  // expected seroprevalence at location & time of serosurvey
  real serofit[NSero];
  
  // mean increase in IFR estimates 10+
  real diff_ifr_b[14]; // 
  real mean_increase_ifr;
  
  // IFRs
  real ifrm65p[4];
  real ifrf65p[4];
  real ifr_m[17];
  real ifr_f[17];
  real ifr_b[17];
  
  // transformed parameters
  for(c in 1:NArea) probInfec[c] = exp(log_probInfec[c]);
  
  // IFRs 65+ 
  for(a in 1:4){
    ifrm65p[a] = deaths65p_m[a]/(pop_m[a+13,indexArea65p]*probInfec[indexArea65p]*relProbInfection[a+13]);
    ifrf65p[a] = deaths65p_f[a]/(pop_f[a+13,indexArea65p]*probInfec[indexArea65p]*relProbInfection[a+13]);
  }
  
  // IFRs all ages
  for(a in 1:13) ifr_m[a] = exp(log_ifr_m[a]);
  for(a in 1:13) ifr_f[a] = exp(log_ifr_f[a]);
  for(a in 1:4){
    ifr_m[13+a] = ifrm65p[a];
    ifr_f[13+a] = ifrf65p[a];
  }
  for(a in 1:17) ifr_b[a] = (ifr_m[a]+ifr_f[a])/2;

  // Estimated deaths by age, sex & region
  for (a in 1:17){
    for(c in 1:NArea){
      natDeath_m[a,c] = pop_m[a,c]*probInfec[c]*ifr_m[a]*relProbInfection[a];
      natDeath_f[a,c] = pop_f[a,c]*probInfec[c]*ifr_f[a]*relProbInfection[a];
      natDeath_b[a,c] = natDeath_f[a,c] + natDeath_m[a,c];
    }
  }
  
  // mean increase in IFRs aged 10+
  for(i in 1:14){
    diff_ifr_b[i] = ifr_b[i+3] - ifr_b[i+2];
  }
  mean_increase_ifr = sum(diff_ifr_b)/14;
  
  // total expected deaths <65 and 65+
  for(c in 1:NArea){
    u65deaths[c] = sum(natDeath_b[1:13,c]);
    o65deaths[c] = sum(natDeath_b[14:17,c]);
  } 
  
  // distribute immunity over time
  for(c in 1:NArea){
    seroT[1:Ndays,c] = (probInfec[c]/deathsT[TdeathsA[c],c])*to_vector(deathsTsero[1:Ndays,c]);
    infecT[1:Ndays,c] = (probInfec[c]/deathsT[TdeathsA[c],c])*to_vector(deathsTinfec[1:Ndays,c]);
  }
  
  // expected seroprevalence at time of serosurveys
  for(i in 1:NSero) serofit[i] = mean(seroT[tmin[i]:tmax[i],SeroAreaIndex[i]]);
}


model {

  real estDeaths_b[13,NArea];
  real estDeaths_m[13,NArea];
  real estDeaths_f[13,NArea];

  // Priors
  for(c in 1:NArea) log_probInfec[c] ~ uniform(-50,1);
  for(a in 1:13) log_ifr_m[a] ~ uniform(-50,-0.001);
  for(a in 1:13) log_ifr_f[a] ~ uniform(-50,-0.001);

  // Fit to age & sex-specific data
  for(c in 1:NArea){
    if(gender[c]==1){
      estDeaths_b[1:NAges[c],c] = alignSUM(natDeath_b[,c], NAges[c], ageG_min[,c], ageG_max[,c]);
      deaths_b[1:NAges[c],c] ~ poisson(estDeaths_b[1:NAges[c],c]);
    }
    if(gender[c]==2){
      estDeaths_m[1:NAges[c],c] = alignSUM(natDeath_m[,c], NAges[c], ageG_min[,c], ageG_max[,c]);
      estDeaths_f[1:NAges[c],c] = alignSUM(natDeath_f[,c], NAges[c], ageG_min[,c], ageG_max[,c]);
      deaths_m[1:NAges[c],c] ~ poisson(estDeaths_m[1:NAges[c],c]);
      deaths_f[1:NAges[c],c] ~ poisson(estDeaths_f[1:NAges[c],c]);
    }
  }
  
  // Likelihood
  for(i in 1:NSero){
    seroprev[i] ~ beta_proportion(mean(seroT[tmin[i]:tmax[i],SeroAreaIndex[i]]), V);
  }
  
}
 
generated quantities {
  
  real ifr_C[NArea]; 
  real ifr_RR[17];
  
  // IFR relative to 55-59 group
  for(a in 1:17) ifr_RR[a] = ifr_b[a]/ifr_b[12];
  
  // Population-weighted IFRs
  for(c in 1:NArea){
    ifr_C[c] = sum(to_vector(ifr_m).*to_vector(pop_m[,c]) + to_vector(ifr_f).*to_vector(pop_f[,c]))/sum(pop_b[,c]);
  }

}


