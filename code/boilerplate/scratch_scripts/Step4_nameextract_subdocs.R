if(!require(readtext)){install.packages('readtext');require(readtext)}
if(!require(tokenizers)){install.packages('tokenizers');require(tokenizers)}
if(!require(pbapply)){install.packages('pbapply');require(pbapply)}
if(!require(data.table)){install.packages('data.table');require(data.table)}
if(!require(doParallel)){install.packages('doParallel');require(doParallel)}
if(!require(stringr)){install.packages('stringr');require(stringr)}
if(!require(tidyverse)){install.packages('tidyverse');require(tidyverse)}
if(!require(pdftools)){install.packages('pdftools');require(pdftools)}
if(!require(googleLanguageR)){install.packages('googleLanguageR')}
if(!require(rvest)){install.packages('rvest')}
#setwd('bucket_mount/tuolumne/')

project = 'scott-davis-remote'
zone = 'us-west1-a'
account_key = 'scratch/scott-davis-remote-56e7dae929b7.json'

Sys.setenv(GCE_AUTH_FILE = account_key,
           GCE_DEFAULT_PROJECT_ID = project,
           GCE_DEFAULT_ZONE = zone)
library(googleLanguageR)
googleLanguageR::gl_auth(json_file = account_key)


pymat = fread('scratch/boilerplate/python_spacy_matcher_person_names.csv')
text_storage = 'input/filtered_text_files/'
flist = list.files(text_storage)
projects_used = fread('scratch/boilerplate/project_candidates_eis_only.csv')
files_used = fread('scratch/boilerplate/document_candidates_eis_only.csv')
tlist = list.files('../eis_documents/enepa_repository/text_as_datatable/',full.names = T, recursive = T)
#entity_file = 'scratch/boilerplate/entity_extraction_results.rds'
#if(!file.exists(entity_file)){ents =list()}else{ents = readRDS(entity_file)}
files_used$FILE_NAME <- str_replace(files_used$FILE_NAME,'\\.pdf$','\\.txt')
#files_used = files_used[!FILE_NAME %in% ents$FILE_NAME,]
keep_tlist = tlist[basename(tlist) %in% files_used$FILE_NAME]




good_string = 'PREPARERS|CONTRIBUTORS|Preparers|Contributors|Consultants|Interdisciplinary Team'#LIST OF PREPARERS|List of Preparers|List Of Preparers|PREPARERS AND CONTRIBUTORS|Preparers and Contributors|Preparers \\& Contributors|Preparers And Contributors'
bad_string = 'TABLE OF CONTENTS|Table of Contents|^CONTENTS|Contents|How to Use This Document|Date Received'

pages_list = pblapply(keep_tlist,function(i) {
  print(i) 
  #i = grep('20170165',keep_tlist,value = T)
  base_file = basename(i)
  id = str_remove(basename(base_file),'_.*')
  #start_dt = data.table(FILE_NAME = base_file,PROJECT_ID = id,people = list(),orgs = list())
  temp_txt =  fread(i,sep = '\t')
  temp_txt$FILE = base_file
  temp_txt$keep = temp_txt$keep2 = 0
  temp_txt$looks_like_frontmatter = !grepl('[A-Z0-9]',str_remove(temp_txt$text,'.*\\s'))
#  temp_txt = temp_txt[grepl('[A-Z0-9]',str_remove(temp_txt$text,'.*\\s')),]
  prep_papers = grepl(good_string,str_sub(temp_txt$text,1,200))&!grepl(bad_string,str_sub(temp_txt$text,1,200))
  temp_txt$keep[prep_papers] <- 1
  prep_papers2 = grepl(good_string,  str_sub(temp_txt$text,nchar(temp_txt$text)-200,nchar(temp_txt$text)))&!grepl(bad_string,  str_sub(temp_txt$text,1,200))
  temp_txt$keep2[prep_papers2] <- 1
  temp_txt = temp_txt[!duplicated(text),]
  temp_txt$count = str_count(temp_txt$text,good_string) - str_count(temp_txt$text,bad_string)


  
  if(any(temp_txt$count[!temp_txt$looks_like_frontmatter>0])){
    temp_txt = temp_txt[!temp_txt$looks_like_frontmatter,]
  }
  if(all(temp_txt$count<=0)&any(temp_txt$keep)){
  temp_txt = temp_txt[keep==1,]  
  }
  temp_txt[,.(Page,count,keep,keep2)]
  temp_txt = temp_txt[Page>=min(temp_txt$Page[which(temp_txt$count==max(temp_txt$count))]),]

  if(any(temp_txt$keep!=0)){
    add = sort(unique(c(sapply(which(temp_txt$keep==1), function(x) x + 0:2))))
    add = add[add<=nrow(temp_txt)]
    temp_txt$keep[add]<-1
  }
  if(any(temp_txt$keep2!=0)){
    add = sort(unique(c(sapply(which(temp_txt$keep2==1), function(x) x + 0:2))))
    add = add[add<=nrow(temp_txt)]
    temp_txt$keep2[add]<-1
  }
  if(any(temp_txt$keep>0|temp_txt$keep2>0)){
    temp_txt = temp_txt[keep==1|keep2==1,]}
  if(all(temp_txt$keep==0&temp_txt$keep2==0)){
    temp_txt = temp_txt[count>0,]
  }
  
    temp_txt = temp_txt[keep!=0|keep2!=0|temp_txt$count>0,]
  #  temp_txt = temp_txt[!grepl('\\.{8,}',text),]
    temp_txt = temp_txt[!{grepl('References Cited|Works Cited|REFERENCES|Index|INDEX',temp_txt$text) & !grepl('Preparers|Contributors|PREPARERS|CONTRIBUTORS',temp_txt$text)},]
     temp_txt
     },cl = 7)
  

pages_dt = rbindlist(pages_list,use.names = T)


#table(projects_used$EIS.Number %in% str_remove(pages_dt$FILE,'_.*'))
#projects_used$EIS.Number[!projects_used$EIS.Number %in% str_remove(pages_dt$FILE,'_.*')]


pages_dt$USE_KEEP2 = pages_dt$FILE %in% pages_dt[,list(sum(keep),sum(keep2)),by=.(FILE)][V1>10&V2>0]$FILE
pages_dt = pages_dt[{!USE_KEEP2}|keep2==1,]
#pages_dt[,.(FILE,Page,count,keep,keep2)][grepl('20130008',FILE),]
saveRDS(pages_dt,'scratch/boilerplate/detected_preparer_pages.RDS')

pages_by_file = split(pages_dt$Page,pages_dt$FILE)
pdf_files = list.files('../eis_documents/enepa_repository/documents/',full.names =T,recursive = T)
index = match(gsub('\\.txt$','.pdf',names(pages_by_file)),basename(pdf_files))

cluster = makeCluster(7)
registerDoParallel(cluster)
clusterEvalQ(cluster,require(data.table))
clusterEvalQ(cluster,require(pdftools))
clusterEvalQ(cluster,require(stringr))
clusterEvalQ(cluster,require(googleLanguageR))
clusterExport(cluster,varlist = list('pdf_files','account_key'))
clusterEvalQ(cluster,googleLanguageR::gl_auth(json_file = account_key))


# clusterEvalQ(cluster,{
# model = 'en_core_web_sm'
# require(spacyr)
# spacy_initialize(model)
# })

#preparer_ids = list.files('scratch/preparer_sections/',full.names = T,recursive = T)

#projects_used$EIS.Number[!projects_used$EIS.Number %in% str_remove(names(pages_by_file),'_.*')]

dir.create('scratch/entity_results/')

file_text = foreach(p =pages_by_file,f = names(pages_by_file),i = stringr::str_remove(names(pages_by_file),'_.*')) %dopar% {
  fl = basename(gsub('txt$','pdf',f))
  fname = paste0('scratch/entity_results/',fl,'.RDS')
  if(!file.exists(fname)){
  tryCatch({
    #p =pages_by_file[1];f = names(pages_by_file)[1];i = str_remove(names(pages_by_file),'_.*')[1]
#fl = basename(gsub('txt$','pdf',f))
fileLocation = grep(basename(gsub('txt$','pdf',f)),pdf_files,value = T,fixed = T)
full_text = pdftools::pdf_text(fileLocation)
tx_string = full_text[p]
print(length(tx_string))
if(length(tx_string)>0){
#tx_split_string = unlist(str_split(tx_string,'\\n'))
#tx_split_string = gsub('(^[A-Z][a-z]+)\\,(\\s[A-Z][a-z]+)','\\1\\2',tx_split_string)
nlp_result <- googleLanguageR::gl_nlp(string = tx_string,nlp_type = 'analyzeEntities',type = 'PLAIN_TEXT',language = 'en')
if(length(nlp_result$entities)==1){ent_temp = data.table(nlp_result$entities)}
if(length(nlp_result$entities)>1){ent_temp = rbindlist(nlp_result$entities,use.names = T,fill = T)}
ent_temp$FILE = f
ent_temp$PROJECT_ID = i
saveRDS(ent_temp,fname)
rm(ent_temp);rm(fname)
#nlp_result$entities
}},error = function(e) NULL)
}
}




ent_set = list.files('scratch/entity_results/',full.names = T,recursive = T)
ent_all = rbindlist(pblapply(ent_set,readRDS,cl = 7),fill = T,use.names = T)

ents_dt = ent_all[type!='NUMBER'&!is.na(type)&mention_type == 'PROPER',]
ents_dt = ents_dt[!ents_dt$name %in% state.name,]

ent_dt = ents_dt
#ent_dt = rbindlist(file_text)
ent_dt$name = str_remove(ent_dt$name,'\\s{4,}.*')
ent_dt = ent_dt[type == 'PERSON',]

ent_dt = ent_dt[!grepl('et_al',name),]
ent_dt = ent_dt[!grepl('_',name),]
ent_dt = ent_dt[grepl('[A-Z]',name),]


ent_dt$name <- str_remove(ent_dt$name,'\\s+$')
#ent_dt$name <- str_remove_all(ent_dt$name,'\\s')
ent_dt$name <- str_remove(ent_dt$name,'_{1,}$')
ent_dt$name <- str_remove(ent_dt$name,'^_{1,}')

ent_dt = ent_dt[!grepl('^[A-Z]\\._[A-Z]',name),]
ent_dt = ent_dt[!grepl('^[A-Z]\\.[A-Z]\\._[A-Z]',name),]
ent_dt = ent_dt[!grepl('^[0-9]',name),]
ent_dt = ent_dt[!grepl('[0-9]{3,}',name),]
ent_dt = ent_dt[!grepl('County',name),]
ent_dt = ent_dt[!grepl('District',name),]
ent_dt = ent_dt[!grepl('^sandy_',name),]

ent_dt = ent_dt[!grepl('Biologist|Planner|Engineer|Environmental|Biology|Wildlife|Grazing|Canyon|Physical|Technician|Land_Use|Nez_Perce|Anchorage|Alaska|Pacific|Oxide|Harvest|Apache|Ranger|Reviewer|Landscape|Geography|Polytechnic|Shoshone|Draft|^Map_|Salmon|Stakeholder|Watershed|Scientist|Fisheries|Design|Specialist|Appendix|Riparian|EIS|Ecologist|University|Raw_Score',name),]

ent_dt = ent_dt[grepl('\\s',name),]


require(tigris)
ngaz = fread('scratch/NationalFile_20210101.txt',sep = '|',fill = T,stringsAsFactors = F,quote = "")
ngaz$CFIPS = ifelse(!is.na(ngaz$COUNTY_NUMERIC),paste0(formatC(ngaz$STATE_NUMERIC,width = 2,flag = '0'),formatC(ngaz$COUNTY_NUMERIC,width = 3,flag = '0')),NA)
ngaz = ngaz[!ngaz$FEATURE_NAME %in% c('Pacific Ocean','South Pacific Ocean','Atlantic Ocean','Gulf of Mexico','Caribbean Sea'),]
ngaz = ngaz[!is.na(ngaz$FEATURE_CLASS),]
ngaz = ngaz[ngaz$STATE_ALPHA %in% c(state.abb,'DC','PR'),]
ngaz = ngaz[!is.na(ngaz$COUNTY_NUMERIC),]
drop_types = c('Tower')
ngaz = ngaz[!ngaz$FEATURE_CLASS %in% drop_types,]
#ngaz = ngaz[!ngaz$FEATURE_NAME %in% c('River','Wilderness','Forest','Lake','Field','Beach','Mountain','Pacific','Atlantic','Earth','Acres','North','South','East','West',state.name),]
gc()
ngaz$FEATURE_NAME2 = str_replace_all(ngaz$FEATURE_NAME,pattern = '\\s','_')

ent_dt = ent_dt[!name %in% ngaz$FEATURE_NAME2,]
ent_dt = ent_dt[!grepl('[A-Z]{3,}',name),]
ent_dt = ent_dt[!grepl('[0-9]{2,}',name),]
ent_dt = ent_dt[!grepl('^([A-Z]\\.){2,}',name),]
ent_dt$name = str_remove(ent_dt$name,'_(–|-|—).*')
ent_dt$name = str_remove(ent_dt$name,'(__|_\\().*')


ent_dt = ent_dt[!grepl('_[a-z]',ent_dt$name),]


ent_dt$PROJECT_ID = str_remove(ent_dt$FILE,'_.*')
ent_dt= ent_dt[name %in% ent_dt[!duplicated(paste(name,PROJECT_ID)),][,.N,by=.(name)][order(-N)][N>1,]$name,]


bad_ents = c('QC_Reference','Date_Received','Wildlife_Biologist',"Environmental_Scientist" ,"Wetland_Geomorphic_Setting"   ,"Environmental_Science" ,
             "Land_Use"   , "Date_Received"   ,"QC_Reference"     , "Wetland_Site_Name" ,"Automatic_Hammer"  ,"Landscape_Architect"  ,"STLC_DI"  ,"Soil_Scientist" ,
             "CDOT_Geot","Wet_Sand_/_Muck_Flats" , "Landscape_Architecture" ,"Marine_Science"  ,"District_Ranger" ,"Colorado_Parks"   ,"Wildlife_Science" ,
             "Kootenai_Tribes" ,"YEH_ASSOCIATES_W_LONG", "Soil_Science", "Earthstar_Geographics"     ,  "Hydrologically_Disconnected","Park_Ranger" ,"STLC_DI__Complete"  ,
             "Endosulfan_II" ,"Endosulfan_Sulfate" ,"STLC_DI__Complete"  , "Douglas_-_fir" ,"Heptachlor_Epoxide","Wildlife_Biology","Land_Use_Permitting",
             "Noise_Specialist","Build_Alternatives","Appendix_D","Realty_Specialist","Virginia_Tech","Wild_Horses","Technical_Reviewer","Endrin_ketone__<","Reduce_Bat_Fatalities" ,
             "Medicine_Bow" ,   "Mark_Udall" , "Juris_Doctor","Planetary_Science"  , "Reducing_Avian_Collisions",    "P.E.__M.S."   , "Mule_Deer",
             "Date_Received__08/08/16","SANDY_CLAYSTONE","Tetra_Tech","Booz_Allen_Hamilton","NAVFAC_Northwest","Cardno_ENTRIX","Raw_Score_/36", "Technical_Memorandum" ,
             "Southeast_Alaska","I.__Soils","Soil_Profile","Hydrologically__Disconnected","Grassy_Forks","Stream_Photograph","Buffalo_PRMP","John_Hickenlooper",
             "Casa_Diablo_IV","Noise_Analyst","Stream_Photograph","Peckham_Ave","Map_ID_Site__Database(s","John_Barrasso","Mt._Baker","Groundwater_Resources",
             "Canada_Lynx","Ute_Mountain_Ute","Dianne_Feinstein","Northwest_Science","Kootenai_Tribe","Word_Processor","Graphic_Artist","Dick_Artley","Jeff_Merkley",
             "Noise_Analysis","Hazardous_Waste","Barbara_Boxer","Juris_Doctorate","Shoshone","Potomac_Yard","A-_Gil","Casa_Diablo_IV","Myotis_sodalis","Klamath_Tribes",
             "Burns_Paiute","Illustrated_Flora","Visual_Resources","Chief_Ranger","Indiana_Bat","PO_Box","PF_Doc","Arizona_Game","Forestry_Technician","P.E.__B.S.",
             "Montana_Fish","Suite_B__LOCATIONS","USDI_Fish","EIS_Reviewer","Page_1","Pool_Bypass","Sherman_Cattle","Good__","Airspeed_Altitude__SEL","SAND_FILL","CH2_M_Hill",
             "Jicarilla_Apache_Tribe","Marine_Mammal_Science"   ,"Mar._Res","Sand_Point_Way_NE"  ,"Fremont Weir","L Margolis",
             "American Indian","Architectural Historian","Forest Supervisor","Native Hawaiian","Native Americans","Shallow Aquitard",
             "TPH_Gasoline_C4-C12" , "CH2_M_HILL","Louis_Berger" ,"Livestock_Grazing", "Endrin_Aldehyde" ,"Amec_Foster_Wheeler" ,"Wildlife_Biology","Bog__Fen","Boise_Idaho","BA_Geography" ,
             'Marl_Seeps',"Juris Doctor" ,"Native American"  ,"Dianne Feinstein" , "Barbara Boxer"  ,"Certified Silviculturist" , "American Midland Naturalist",
             "John Day","Responsible Official",'Confederated Salish','Confederated Tribes','Dick Artley','Wild Horse',"Theodore Roosevelt",
             "Forest Botanist","Migratory Birds","Ron Wyden","John Barrasso","Interdisciplinary Team Members","Longworth H.O.B.","John Muir Project","Title VI","Odobenus rosmarus divergens")
             

ent_dt = ent_dt[!name%in% bad_ents,]
ent_dt = ent_dt[!grepl('^[A-Z]\\.',name),]

##for spacy code, this catches cases whre First Last and Last First are identical
#splts = str_split(ent_dt$name,'_',simplify = F)
#pairs = sapply(splts,function(x) if(paste(x[2],x[1],sep = '_') %in% ent_dt$name){c(paste(x[2],x[1],sep = '_'),paste(x[1],x[2],sep = '_'))})
#pairs = lapply(pairs[!sapply(pairs,is.null)],sort)

#for(p in pairs){
#  ent_dt$name[ent_dt$name %in% p] <- p[1]
#}

person_dt[name=='Adam Smith']
person_dt[!is.na(wikipedia_url),][,.N,by=.(name)][order(-N)]
person_dt = ent_dt
person_dt[,.N,by=.(name)][order(-N)]
person_dt

file_text = readRDS(sort(list.files('scratch/boilerplate/',pattern = 'raw_entity_pull_',full.names = T),decreasing = T)[1])
ent_dt = file_text
ent_dt$PROJECT_ID <- str_remove(ent_dt$FILE,'_.*')
#ent_dt = ent_dt[grepl('[A-Za-z0-9]',name),]
ent_dt = ent_dt[grepl('[A-Z]',name),]
ent_dt = ent_dt[!grepl('[0-9]{3,}',name),]
ent_dt = ent_dt[!grepl('[0-9]$',name),]
ent_dt$name = str_remove(ent_dt$name,'\\s{4,}.*')
ent_dt = ent_dt[!grepl('http',name,perl = T),]
ent_dt = ent_dt[!grepl('\\=',name,perl = T),]
ent_dt = ent_dt[!name %in%state.name,]
# drop all names observed in more than 100 EISs


ent_dt = ent_dt[!name %in% ent_dt[!duplicated(paste(name,PROJECT_ID)),.N,by=.(name)][order(-N),][N>80,]$name,]

ent_dt = ent_dt[!grepl('\\(',ent_dt$name),]

#full_tlist <- readRDS('scratch/boilerplate/big_text_files/big_eis_text.rds')
ent_dt$name[grepl('STRATIFIED ENVIRONMENTAL (&|AND) ARCHAEOLOGICAL',toupper(ent_dt$name))] <- "STRATIFIED ENVIRONMENTAL & ARCHAEOLOGICAL SERVICES, LLC"
ent_dt$name[grepl('WALSH ENVIRON',toupper(ent_dt$name))] <- "WALSH ENVIRONMENTAL SCIENTISTS AND ENGINEERS, LLC"
ent_dt$name[grepl('KERLINGER',toupper(ent_dt$name))] <- "CURRY & KERLINGER, LLC"
ent_dt$name[grepl('SOLV LLC',toupper(ent_dt$name))|toupper(ent_dt$name)=='SOLV'] <- 'SOLVE, LLC'
ent_dt$name[grepl('GRETTE ASSOC',toupper(ent_dt$name))] <- "GRETTE ASSOCIATES, LLC"
ent_dt$name[grepl('^HELIA ENV',toupper(ent_dt$name))] <- "HELIA ENVIRONMENTAL, LLC"
ent_dt$name[grepl('PEAK ECOLOG',toupper(ent_dt$name))] <- "PEAK ECOLOGICAL SERVICES, LLC"
ent_dt$name[grepl('ALPINE GEOPHYSICS',toupper(ent_dt$name))] <- "ALPINE GEOPHYSICS, LLC"
ent_dt$name[grepl("HAYDEN(\\s|-)WING",toupper(ent_dt$name))]<- "HAYDEN-WING ASSOCIATES, LLC"
ent_dt$name[grepl("WILD TROUT ENTERPRISES",toupper(ent_dt$name))] <- "WILD TROUT ENTERPRISES, LLC"
ent_dt$name[grepl("ZEIGLER GEOLOGIC",toupper(ent_dt$name))] <- "ZEIGLER GEOLOGIC CONSULTING, LLC"
ent_dt$name[grepl("NORTHERN LAND USE",toupper(ent_dt$name))] <- "NORTHERN LAND USE RESEARCH ALASKA, LLC"
ent_dt$name[grepl("LEGACY LAND",toupper(ent_dt$name))] <- "LEGACY LAND & ENVIRONMENTAL SOLUTIONS, LLC"
ent_dt$name[grepl("SOUTHWEST GEOPHY",toupper(ent_dt$name))] <- 'SOUTHWEST GEOPHYSICAL CONSULTING, LLC'
ent_dt$name[grepl("SYRACUSE ENVIRONMENTAL RESEARCH ASSOCIATES",toupper(ent_dt$name))] <- "SYRACUSE ENVIRONMENTAL RESEARCH ASSOCIATES"
ent_dt$name[grepl("ANDERSON PERRY (&|AND) ASSOCIATES",toupper(ent_dt$name))] <- "ANDERSON PERRY & ASSOCIATES, INC." 
ent_dt$name[grepl("VEATCH",toupper(ent_dt$name))] <- "BLACK & VEATCH" 


ent_dt$name[grepl("TETRA TECH",toupper(ent_dt$name))] <- "TETRA TECH INC." 
ent_dt$name[grepl("FLUOR",toupper(ent_dt$name))] <- "FLUOR CORP." 
ent_dt$name[grepl('\\bERM\\b',ent_dt$name)] <- "ERM" 
ent_dt$name[grepl('\\b(Kiewit|KIEWIT)\\b',ent_dt$name)] <- "KIEWIT CORP." 
ent_dt$name[grepl('\\b(ARCADIS|Arcadis)\\b',ent_dt$name)] <- "ARCADIS NV" 
ent_dt$name[grepl('\\bECC\\b',ent_dt$name)] <- "ECC" 
ent_dt$name[grepl('CDM.*SMITH',toupper(ent_dt$name))] <- "CDM SMITH" 
ent_dt$name[grepl('^Jacobs(\\W|$)|^JACOBS(\\W|$)',ent_dt$name)]<-'JACOBS ENGINEERING GROUP'

ent_dt$name[grepl('PARSONS BRINCKERHOFF|PARSONS BRINKERHOFF',toupper(ent_dt$name))] <- "WSP" 


ent_dt$name[grepl('LOUIS.*BERGER',toupper(ent_dt$name))] <- "LOUIS BERGER" 
#note this next example is why toupper is not made permanent -- megawatt hours are written as MWh
ent_dt$name[grepl('\\bMWH\b',ent_dt$name)] <- "MWH CONSTRUCTORS, INC." 
ent_dt$name[grepl("MOTT MACDONALD",toupper(ent_dt$name))] <- "MOTT MACDONALD" 

ent_dt$name[grepl("AECOM",toupper(ent_dt$name))] <- "AECOM" 
ent_dt$name[grepl("RAMBOLL",toupper(ent_dt$name))] <- "RAMBOLL"
ent_dt$name[grepl("BATTELLE",toupper(ent_dt$name))] <- "BATTELLE"
ent_dt$name[grepl("GOLDER ASSOCIATES",toupper(ent_dt$name))] <-"GOLDER ASSOCIATES CORP."
ent_dt$name[grepl('ICF',ent_dt$name)] <- 'ICF INTERNATIONAL'
ent_dt$name[grepl('LEIDOS',toupper(ent_dt$name))] <- 'LEIDOS INC.'

ent_dt$name[grepl('PARSONS TRANSPORTATION GROUP|PARSONS HBA|PARSONS HARLAND BARTHOLOMEW|PARSONS INFRASTRUCTURE AND TECHNOLOGY|PARSONS GOVERNMENT SERVICES',toupper(ent_dt$name))] <-'PARSONS CORPORATION'

ent_dt$name[grepl('^PARSONS',toupper(ent_dt$name))] <- 'PARSONS CORPORATION'


ent_dt$name[grepl('CARDNO',toupper(ent_dt$name))] <- 'CARDNO'


ent_dt$name[grepl('STANTEC',toupper(ent_dt$name))] <- 'STANTEC INC.'
ent_dt$name[grepl('PARAMETRIX',toupper(ent_dt$name))] <- 'PARAMETRIX INC.'
ent_dt$name[grepl('SWCA ENVIRONMENTAL',toupper(ent_dt$name))] <- 'SWCA ENVIRONMENTAL CONSULTANTS'
ent_dt$name[grepl('CH2M',toupper(ent_dt$name))] <- 'CH2M HILL'



ent_dt = ent_dt[nchar(ent_dt$name)>1,]
ent_dt = ent_dt[str_count(ent_dt$name,'[0-9]')<=2,]
ent_dt = ent_dt[!tolower(ent_dt$name) %in% stopwords::stopwords(),]
ent_dt = ent_dt[!name %in% person_dt$name,]
ent_dt = ent_dt[!grepl(paste(state.name,collapse = '|'),name,perl =T),]



ent_dt = ent_dt[!name%in%c('Notes','Material','Rock','SAND','Qualifications','Presence','Yes','Size','FINAL','Corridor','NF',"Tim Parsons","John Parsons",'Reclamation','Reference','C-17','Present','Mineral','RESOURCE','EIR',"NPS","INC","NP",'Sample','Bachelor','Sheet','Author','WATER','Tier','Mr.','Type','ASSOCIATES',"RMP","CEQA","USCS","USGS",'Page','Little',"PAGE","England",'Pond',"Wood",'Sam','SAM','Johnson','Fullerton','Payette'),]
ent_dt = ent_dt[!name%in%state.abb,]


firm_scrapes = readRDS('scratch/enr_firm_lists.RDS')
nms = unlist(firm_scrapes)
clean_names = unique(str_remove(nms,'\\,.+'))
clean_names = unique(str_remove(clean_names,'\\s\\(.+'))
clean_names = gsub('|','\\|',clean_names,fixed = T)
clean_names = gsub('&','\\&',clean_names,fixed = T)
clean_names = gsub('\\s{1,}',' ',clean_names)
clean_names = unique(clean_names)


person_dt = person_dt[!str_replace_all(name,'_',' ') %in% clean_names,]
saveRDS(person_dt,'scratch/boilerplate/person_entities_extracted.RDS')

uq_names = unique(ent_dt$name);length(uq_names)
mcores = 4
match1 = pblapply(clean_names,function(x) {grep(paste0('\\b',x,'\\b'),uq_names,perl = T)})
match2 = pblapply(tm::removePunctuation(clean_names),function(x) grep(paste0('\\b',x,'\\b'),uq_names,perl = T),cl = mcores)
match3 = pblapply(str_remove(clean_names,'\\s(Inc\\.$|LLC$|LLC\\.$|Corp\\.$)'),function(x) grep(paste0('\\b',x,'\\b'),uq_names,perl = T),cl = mcores)
match1A = pblapply(toupper(clean_names),function(x) {grep(paste0('\\b',x,'\\b'),toupper(uq_names),perl = T)},cl = mcores)
match2B = pblapply(tm::removePunctuation(toupper(clean_names)),function(x) grep(paste0('\\b',x,'\\b'),toupper(uq_names),perl = T),cl = mcores)
match3C = pblapply(str_remove(toupper(clean_names),'\\sINC\\.$|\\sLLC$|\\sLLC\\.$|\\sCORP\\.$'),function(x) grep(paste0('\\b',x,'\\b'),toupper(uq_names),perl = T),cl = mcores)

# # # # #

consult_matches = mapply(function(m1,m2,m3,m4,m5,m6) unique(c(m1,m2,m3,m4,m5,m6)),m1 = match1,m2 = match2,m3 = match3,m4 = match1A,m5 = match2B,m6 = match3C)

consult_dt = rbindlist(lapply(seq_along(clean_names),function(i) data.table(clean_names[i],uq_names[consult_matches[[i]]])),use.names = T,fill = T)[!is.na(V2),]


orgs = ent_dt
orgs$NAME = toupper(orgs$name)
orgs$CONSULTANT <- consult_dt$V1[match(orgs$name,consult_dt$V2)]
orgs = orgs[orgs$CONSULTANT!='SAM LLC']
other_consultants =  c("STRATIFIED ENVIRONMENTAL & ARCHAEOLOGICAL SERVICES, LLC",
                       "WALSH ENVIRONMENTAL SCIENTISTS AND ENGINEERS, LLC",
                       "CURRY & KERLINGER, LLC",
                       'SOLVE, LLC',
                       "GRETTE ASSOCIATES, LLC",
                       "HELIA ENVIRONMENTAL, LLC",
                       "PEAK ECOLOGICAL SERVICES, LLC",
                       "ALPINE GEOPHYSICS, LLC",
                       "HAYDEN-WING ASSOCIATES, LLC",
                       "WILD TROUT ENTERPRISES, LLC",
                       "ZEIGLER GEOLOGIC CONSULTING, LLC",
                       "NORTHERN LAND USE RESEARCH ALASKA, LLC",
                       "LEGACY LAND & ENVIRONMENTAL SOLUTIONS, LLC",
                       'SOUTHWEST GEOPHYSICAL CONSULTING, LLC',
                       "ALPINE ENVIRONMENTAL CONSULTANTS, LLC",
                       "SYRACUSE ENVIRONMENTAL RESEARCH ASSOCIATES",
                       "NUTTER AND ASSOCIATES",
                       "GARCIA AND ASSOCIATES","HORIZON ENVIRONMENTAL SERVICES, INC.",
                       "WESTERN ECOSYSTEMS TECHNOLOGY, INC.",
                       "ANDERSON PERRY & ASSOCIATES, INC." )

orgs$CONSULTANT[toupper(orgs$name) %in% other_consultants] <- toupper(orgs$name[toupper(orgs$name) %in% other_consultants])

orgs$CONSULTANT <- toupper(orgs$CONSULTANT)
orgs = orgs[!is.na(CONSULTANT),]
orgs = orgs[!CONSULTANT%in%c('PAYETTE','MCMAHON','HYDROGEOLOGIC INC.','WOOD','LITTLE','PAGE','CRAWFORD','NELSON','HERBERT','WHITMAN','Johnson','JOHNSON','POND','Whitman','BOWEN','STEWART','ENGLAND','HUNT','Crawford','Page','SAM LLC','Cathy Bechtel','Little','EXP'),]

handcoded_firms = orgs[NAME %in% other_consultants,.(PROJECT_ID,NAME)]
setnames(handcoded_firms,'NAME','FIRM')
autocoded_firms = orgs[grepl('CONSULTING|CONSULTANTS',NAME),.(PROJECT_ID,NAME)]
setnames(autocoded_firms,'NAME','FIRM')
detected_firms = orgs[!is.na(CONSULTANT),.(PROJECT_ID,CONSULTANT)]
setnames(detected_firms,'CONSULTANT','FIRM')

consults = rbindlist(list(detected_firms,handcoded_firms,autocoded_firms))
consults$FIRM <- toupper(consults$FIRM)
consults = consults[!duplicated(consults),]
consults[,.N,by=.(FIRM)][order(-N)][1:20]

orgs[!duplicated(paste(CONSULTANT,PROJECT_ID)),.N,by=.(CONSULTANT)][order(-N)][1:20,]

orgs[CONSULTANT=='WSP']

orgs[PROJECT_ID=='20160133']

orgs[!duplicated(paste(PROJECT_ID,CONSULTANT)),.N,by=.(CONSULTANT)][order(-N)][1:30]



consults$FIRM<-str_replace_all(consults$FIRM,'\\,','')





consults[!duplicated(PROJECT_ID,FIRM),.N,by=.(FIRM)][order(-N)][1:20,]



orgs[starts_with&!is.na(CONSULTANT),][,.N,by=.(CONSULTANT)][order(-N)][1:30,]


orgs[CONSULTANT=='WOOD',]$NAME

orgs

orgs[CONSULTANT=='NELSON']

orgs[{grepl('\\s',orgs$CONSULTANT)}|{!grepl('\\s',orgs$CONSULTANT) & orgs$CONSULTANT==orgs$NAME},][!duplicated(paste(PROJECT_ID,CONSULTANT)),][,.N,by=.(CONSULTANT)][order(-N),][1:20,]
person_dt[PROJECT_ID=='20130120',]

starts_with = as.vector(mapply(function(x,y) grepl()
  
  ,x = orgs$CONSULTANT,y = toupper(orgs$name)))




test = orgs[starts_with&!is.na(CONSULTANT),]
test[CONSULTANT=='LITTLE']




orgsstarts_with | grepl('\\s',orgs$name),]


orgs[is.na(CONSULTANT),][,.N,by=.(NAME)][order(-N)][1:30,]
  
       orgs[NAME=='SMITH']
       
       
       x = orgs[,.N,by=.(CONSULTANT)][order(-N)]



orgs = ent_dt
orgs[!name %in% orgs[,.N,by=.(name)][N>1,]$name,]$name
#drop all names observed only 1 time
orgs = orgs[name %in% orgs[,.N,by=.(name)][N>1,]$name,]



#length(unique(toupper(clean_names)))
#orgs$name = orgs$name

#orgs = orgs[name %in% orgs[!duplicated(paste(name,PROJECT_ID)),.N,by=.(name)][N>1,]$name,]



orgs$type[orgs$CONSULTANT %in% c("CDM Smith","Parametrix","MOTT MACDONALD","Leidos",'WSP',"HNTB","Tetra Tech Inc.","Louis Berger","RK\\&K","Michael Baker International",
"Black \\& Veatch","AECOM","ICF","GRAEF","Atkins North America","HDR","POTOMAC-HUDSON ENGINEERING, INC.","STOLLER-NAVARO","SCIENCE APPLICATIONS INTERNATIONAL CORPORATION")]<-'ORGANIZATION'
#orgs$CONSULTANT[grep('ICF',orgs$CONSULTANT)] <- 'ICF International'





saveRDS(orgs,'scratch/consultant_project_matches_V2.RDS')


orgs

fwrite(projects_used[,.(EIS.Number,AGENCY,EIS.Title)],'input/preparer_consultants.csv')



consultant_project_matches = pblapply(seq_along(name_matches),function(x) {data.table(PROJECT_ID = orgs$PROJECT_ID[name_matches[[x]]],FIRM = clean_names[x])})
saveRDS(consultant_project_matches,'scratch/consultant_project_matches_V2.RDS')

consultant_project_matches = readRDS('scratch/consultant_project_matches_V2.RDS')

consults = rbindlist(consultant_project_matches)[!is.na(PROJECT_ID)]
consults$FIRM = toupper(consults$FIRM)
consults = consults[!duplicated(consults),]

handcoded_firms = orgs[NAME %in% other_consultants,.(PROJECT_ID,NAME)]
setnames(handcoded_firms,'NAME','FIRM')
autocoded_firms = orgs[grepl('CONSULTING|CONSULTANTS',NAME),.(PROJECT_ID,NAME)]
setnames(autocoded_firms,'NAME','FIRM')

consults = rbindlist(list(consults,handcoded_firms,autocoded_firms))
consults = consults[!duplicated(consults),]

consult_Freq = consults[PROJECT_ID %in%projects_used$EIS.Number,][,.N,by = .(FIRM)][order(-N)][N>=5,]



#consults[PROJECT_ID %in% epa_record$EIS.Number,][,.N,by = .(FIRM)][order(-N)][1:25,]

outdir.tables = "output/boilerplate/tables/" 
tableout <-htmlTable(consult_Freq)
outdir.tables = "output/boilerplate/tables/" 
sink(paste0(outdir.tables,"consultant_table.html"))
print(tableout,type="html",useViewer=F)
sink()



library(pdftools)
library(tabulizer)
library(rJava)
library(data.table)
library(rvest)
library(stringr)
tabs = '.flush-left td , th'
prepares = fread('../tuolumne/scratch/boilerplate/preparedocs.csv')

firms = rbindlist(list(read_html(top100) %>% html_nodes('table') %>% .[[2]] %>% html_table(trim=T,fill=T),
                       read_html(top200) %>% html_nodes('table') %>% .[[2]] %>% html_table(trim=T,fill=T)),use.names=T)

splits = str_split(firms$FIRM,',')
firms$NAME = sapply(splits,function(x) x[[1]])



