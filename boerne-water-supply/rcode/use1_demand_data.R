###################################################################################################################################################
#
# CODE TO READ IN SENSOR OF THINGS DATA FOR NC WATER SUPPLY DASHBOARD
# CREATED BY LAUREN PATTERSON & KYLE ONDA @ THE INTERNET OF WATER
# FEBRUARY 2021
# Modified November 2021 by Vianey Rueda for Boerne
#
###################################################################################################################################################


#REFERENCE INFO
#https://gost1.docs.apiary.io/#reference/odata-$filter
#observed properties: https://twsd.internetofwater.dev/api/v1.0/ObservedProperties

######################################################################################################################################################################
#
#   Load Old Data
#
######################################################################################################################################################################
#load in geojson for utilities
utilities <- read_sf(paste0(swd_data, "utility.geojson")); 
pwsid.list <- unique(utilities$pwsid) #Boerne is the utility of interest
mymonths <- c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"); #used below to convert numbers to abbrev
#mapview::mapview(utilities)

#read in old data
old_total_demand <- read.csv(paste0(swd_data, "demand/historic_total_demand.csv"))
old_demand_by_source <- read.csv(paste0(swd_data, "demand/historic_demand_by_source.csv"))
old_reclaimed <- read.csv(paste0(swd_data, "demand/historic_reclaimed_water.csv"))
old_pop <- read.csv(paste0(swd_data, "demand/historic_pop.csv"))

#calculate moving average function
ma <- function(x,n=7){stats::filter(x,rep(1/n,n), sides=1)}


######################################################################################################################################################################
#
# Read in new water demand data
#
#####################################################################################################################################################################
gs4_auth()
1

demand_data <- read_sheet("https://docs.google.com/spreadsheets/d/1BKb9Q6UFEBNsGrLZhjdq2kKX5t1GqPFCWF553afUKUg/edit#gid=2030520898", sheet = 1, range = "A229:H", col_names = FALSE,col_types = "Dnnnnnnn")
demand_by_source <- demand_data[, c("...1", "...2", "...3", "...6", "...7", "...8")]

#rename columns
demand_by_mgd <- rename(demand_by_source, date = "...1", groundwater = "...2", boerne_lake = "...3", GBRA = "...6", reclaimed = "...7", total = "...8")

#replace na's with 0s
demand_by_mgd <- as.data.frame(demand_by_mgd)
demand_by_mgd[is.na(demand_by_mgd)] <- 0

demand_by_mgd <- as.data.frame(demand_by_mgd)

#change units to MGD
demand_by_mgd$groundwater <- demand_by_mgd$groundwater/1000; demand_by_mgd$boerne_lake <- demand_by_mgd$boerne_lake/1000; demand_by_mgd$GBRA <- demand_by_mgd$GBRA/1000; demand_by_mgd$reclaimed <- demand_by_mgd$reclaimed/1000; demand_by_mgd$total <- demand_by_mgd$total/1000; 

#include PWSId
demand_by_mgd$pwsid <- utilities$pwsid

#add julian indexing
#nx <- demand_by_mgd %>% mutate(year = year(date), month = month(date), day = day(date))
nx <- demand_by_mgd %>% mutate(year = year(date), day_month = substr(date, 6, 10))

for(i in 1:nrow(nx)) { #computationally slow. There's almost certainly a faster way. But it works. 
  
  if(leap_year(nx$year[i]) == TRUE) {nx$julian[i] <- julian.ref$julian_index_leap[julian.ref$day_month_leap == nx$day_month[i]]}
  if(leap_year(nx$year[i]) == FALSE) {nx$julian[i] <- julian.ref$julian_index[julian.ref$day_month == nx$day_month[i]]}
  
  print(paste(round(i/nrow(nx)*100,2),"% complete"))
}

demand_by_mgd <- nx

#split date by month and day
demand_by_mgd = demand_by_mgd %>% 
  mutate(date = ymd(date)) %>% 
  mutate_at(vars(date), funs(year, month, day))

demand_by_mgd$day <- as.numeric(demand_by_mgd$day)

str(demand_by_mgd)

new_demand_by_mgd <- demand_by_mgd %>% filter(year >= 2022 & date < today)
new_demand_by_mgd$date <- format(as.Date(new_demand_by_mgd$date), "%Y-%m-%d") # make sure the date format is the same for old and new before binding

#remove days that don't have data (utilities director includes 0's for days he hasn't input data yet)
new_demand_by_mgd <- filter(new_demand_by_mgd, groundwater > 0, boerne_lake > 0, GBRA > 0, reclaimed > 0)

#merge old and new data
all_demand_by_mgd <- rbind(old_demand_by_source, new_demand_by_mgd) 

check.last.date <- all_demand_by_mgd %>% filter(date == max(date)) %>% dplyr::select(date, month)
table(check.last.date$date)

#write.csv
write.csv(demand_by_mgd, paste0(swd_data, "demand/all_demand_by_source.csv"), row.names=FALSE)


#include month abbreviations
demand2 <- all_demand_by_mgd %>% group_by(pwsid) %>% mutate(julian = as.numeric(strftime(date, format = "%j")), month = month(date), monthAbb = mymonths[month], year = year(date))

#calculate mean demand
demand2 <- all_demand_by_mgd %>% mutate(date = as.Date(substr(date,1,10),format='%Y-%m-%d')) 
demand3 <- demand2 %>% group_by(pwsid) %>% arrange(date) %>% mutate(timeDays = as.numeric(date - lag(date)))
demand4 <- demand3 %>% group_by(pwsid) %>% mutate(mean_demand = ifelse(timeDays <= 3, round(as.numeric(ma(total)),2), total), 
                                                  julian = as.numeric(strftime(date, format = "%j")), month = month(date), monthAbb = mymonths[month], year = year(date))
demand5 <- demand4 %>% mutate(total = round(total,2), mean_demand = ifelse(is.na(mean_demand)==TRUE, total, mean_demand))

#calculate monthly peak
demand6 <- demand5 %>% group_by(pwsid, month, year) %>% mutate(peak_demand = round(quantile(total, 0.98),1)); #took the 98% to omit outliers

#provide julian date
demand7 <- demand6 %>% mutate(date2 = date, date = paste0(monthAbb,"-",day(date2))) %>% select(-timeDays)

#clean up 
demand7 <- rename(demand7, demand_mgd = "total")
demand7 <- demand7[, c("pwsid", "date","demand_mgd", "mean_demand", "julian", "month", "monthAbb", "year", "peak_demand", "date2")]

#write.csv
write.csv(demand7, paste0(swd_data, "demand/all_total_demand.csv"), row.names=FALSE)


#create comulative demand
demand.data <- demand7 %>% filter(date2>start.date)
foo.count <- demand.data %>% group_by(pwsid, year) %>% count() %>% filter(year < current.year & n>340 | year == current.year) %>% mutate(idyr = paste0(pwsid,"-",year)) 
foo.cum <- demand.data %>% mutate(idyr = paste0(pwsid,"-",year)) %>% filter(idyr %in% foo.count$idyr) %>% arrange(pwsid, year, month, date2)
foo.cum <- foo.cum %>% distinct() %>% filter(year>=2000); #shorten for this file

foo.cum2 <- foo.cum %>% arrange(pwsid, year, julian) %>% dplyr::select(pwsid, year, date, julian, demand_mgd) %>% distinct() %>% 
  group_by(pwsid, year) %>% mutate(demand_mgd2 = ifelse(is.na(demand_mgd), 0, demand_mgd)) %>%  mutate(cum_demand = cumsum(demand_mgd2)) %>% dplyr::select(-demand_mgd, -demand_mgd2) %>% rename(demand_mgd = cum_demand) %>% distinct()

table(foo.cum$pwsid, foo.cum$year)
#in case duplicate days - take average
foo.cum3 <- foo.cum2 %>% group_by(pwsid, year, julian, date) %>% summarize(demand_mgd = round(mean(demand_mgd, na.rm=TRUE),2), .groups="drop") %>% distinct()

write.csv(foo.cum3, paste0(swd_data, "demand/all_demand_cum.csv"), row.names=FALSE)


######################################################################################################################################################################
#
# Reclaimed water data
#
#####################################################################################################################################################################
new_reclaimed <- subset(new_demand_by_mgd, select = -c(total,groundwater,boerne_lake,GBRA))

all_reclaimed <- rbind(old_reclaimed, new_reclaimed)

#include month abbreviations
all_reclaimed2 <- all_reclaimed %>% group_by(pwsid) %>% mutate(julian = as.numeric(strftime(date, format = "%j")), month = month(date), monthAbb = mymonths[month], year = year(date))

#calculate mean demand
all_reclaimed2 <- all_reclaimed2 %>% mutate(date = as.Date(substr(date,1,10),format='%Y-%m-%d')) 
all_reclaimed3 <- all_reclaimed2 %>% group_by(pwsid) %>% arrange(date) %>% mutate(timeDays = as.numeric(date - lag(date)))
all_reclaimed4 <- all_reclaimed3 %>% group_by(pwsid) %>% mutate(mean_reclaimed = ifelse(timeDays <= 3, round(as.numeric(ma(reclaimed)),2), reclaimed), 
                                                  julian = as.numeric(strftime(date, format = "%j")), month = month(date), monthAbb = mymonths[month], year = year(date))
all_reclaimed5 <- all_reclaimed4 %>% mutate(reclaimed = round(reclaimed,2), mean_reclaimed = ifelse(is.na(mean_reclaimed)==TRUE, reclaimed, mean_reclaimed))

#calculate monthly peak
all_reclaimed6 <- all_reclaimed5 %>% group_by(pwsid, month, year) %>% mutate(peak_reclaimed = round(quantile(reclaimed, 0.98),1)); #took the 98% to omit outliers

#provide julian date
all_reclaimed7 <- all_reclaimed6 %>% mutate(date2 = date, date = paste0(monthAbb,"-",day(date2))) %>% select(-timeDays)

#write.csv
all_reclaimed8 <- subset(all_reclaimed7, select = c(pwsid, date, reclaimed, mean_reclaimed, julian, month, monthAbb, year, peak_reclaimed, date2))
write.csv(all_reclaimed8, paste0(swd_data, "demand/all_reclaimed_water.csv"), row.names=FALSE)

#calculate percent of total
all_reclaimed9 <- all_reclaimed8
all_reclaimed9$total <- all_demand_by_mgd$total
all_reclaimed9$percent_of_total <- (all_reclaimed9$reclaimed/all_reclaimed9$total)*100

#write.csv
write.csv(all_reclaimed9, paste0(swd_data, "demand/all_reclaimed_percent_of_total.csv"), row.names=FALSE)


######################################################################################################################################################################
#
# Read in new pop data
#
#####################################################################################################################################################################
all_city_data <- read_sheet("https://docs.google.com/spreadsheets/d/1BKb9Q6UFEBNsGrLZhjdq2kKX5t1GqPFCWF553afUKUg/edit#gid=2030520898", sheet = 1, range = "A4245:K", col_names = FALSE)

#filter for pop data only
all_pop_data <- all_city_data[,c("...1", "...10", "...11")]

#rename columns
pop_data <- rename(all_pop_data, date = "...1", clb_pop = "...10", wsb_pop = "...11")
pop_data <- as.data.frame(pop_data)

#remove na's
pop_data <- na.omit(pop_data)

#add julian indexing
nxx <- pop_data %>% mutate(year = year(date), day_month = substr(date, 6, 10))

for(i in 1:nrow(nxx)) { #computationally slow. There's almost certainly a faster way. But it works. 
  
  if(leap_year(nxx$year[i]) == TRUE) {nxx$julian[i] <- julian.ref$julian_index_leap[julian.ref$day_month_leap == nxx$day_month[i]]}
  if(leap_year(nxx$year[i]) == FALSE) {nxx$julian[i] <- julian.ref$julian_index[julian.ref$day_month == nxx$day_month[i]]}
  
  print(paste(round(i/nrow(nxx)*100,2),"% complete"))
}

pop_data <- nxx

#split date by month and day
pop_data = pop_data %>% 
  mutate(date = ymd(date)) %>% 
  mutate_at(vars(date), funs(year, month, day))

#include pwsid
pop_data$pwsid <- "TX300001"

new_pop_data <- pop_data %>% filter(year >= 2022)

# merge old and new pop data
all_pop_data <- rbind(old_pop, new_pop_data)

#write.csv
write.csv(pop_data, paste0(swd_data, "demand/all_pop.csv"), row.names=FALSE)

################################################################################################################################################################
# remove all except for global environment 
rm(list= ls()[!(ls() %in% c('julian.ref','update.date', 'current.month', 'current.year', 'end.date', 'end.year', 
                            'mymonths', 'source_path', 'start.date', 'state_fips', 'stateAbb', 'stateFips', 'swd_data', 'today', 
                            '%notin%', 'ma'))])
