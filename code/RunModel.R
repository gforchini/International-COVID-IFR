library(rstan)

# Source functions
source('./code/FunctionsForIFR.R')


#----- Data Inputs -----#

# Age-specific death data
df <- read.csv('./data/deaths_age.csv')
df <- df[df$nat.reg=='nat', ] # national-level only
countries <- sort(as.character(unique(df$country)))
df <- agg_deathsAp(df, countries, 80) # aggregate 80+ age groups
df <- agg_deathsu5(df, countries) # aggregate ages <4
df$age_max[df$age_max==17] <- 19 # where 17/18 is used as an age-band, switch to 19/20 (Greece & NYC only)
df$age_min[df$age_min==18] <- 20
dfU65 <- df[df$age_max<65, ]


# Adjusted death data 65+
df65p <- read.csv('./data/deaths_age_adjusted.csv')
df65p <- df65p[df65p$country=='England',]
df65p <- agg_deathsAp(df65p, 'England', 80)
df65p <- df65p[df65p$age_min>63, ]

# Demographic data
poplist <- list()
for(k in unique(countries)){
  poplist[[k]] <- read.csv(paste('./data/population/', k,'-2019.csv', sep=''))
} 

# Serology data
sero <- read.csv('./data/serostudies.csv')
sero$region <- as.character(sero$region)
sero <- sero[sero$region %in% countries, ]
sero <- sero[!sero$n_pos==0, ]

# Death time series from Johns Hopkins repo
deathsT <- read.csv('data/time_series_covid19_deaths_global.csv')
deathsTR <- read.csv('data/deathsT_region.csv') # time series not included in Johns Hopkins repo
deathsT <- tidy_deathsT(deathsT, deathsTR, countries)

# Distribute deaths backwards for timing of seroconversion & infection
g <- delay_deaths(deathsT, countries)


# List of inputs for model
Inputs <- get_inputs(countries, poplist, dfU65, df65p, deathsT, sero, NAges=13)
Inputs$deathsTinfec <- g$deathsTinfec
Inputs$deathsTsero <- g$deathsTsero
Inputs$relProbInfection <- c(rep(1,13),0.7,0.7,0.7,0.7) 


#----- Run model -----#
fit <- runStan(model='code/IFRinternational_ensemble.stan', Inputs, N_iter=10000, N_chains=3, max_td=15, ad=0.95)


# Check convergence
chains <- rstan::extract(fit)
traceplot(fit, pars=names(fit)[1:10])
stan_dens(fit, pars=names(fit)[1:10])



#----- Model outputs -----#

# IFR estimates & plots
ifrAge <- plot_IFR_age(chains, Inputs)
ifrPop <- plot_IFR_area(chains, Inputs, countries)
ifrAge$ifrAp
ifrPop$ifrCp

# Observed & expected seroprevalence values
lambdaFit <- serofit(chains, sero)


# Seroprevalence time series plots
continent <- vector()
for(i in 1:length(countries)) continent[i] <- paste(df$continent[df$country==countries[i]][1])
seroT <- sero_time(chains, Inputs, countries, continent)
imm <- plot_immunity(chains, Inputs, countries, plotfit=T)
imm[[3]]

# Fit to age data
plotFit <- fit_deaths(chains, Inputs, dfU65, countries)
plotFit$plots[[3]]





