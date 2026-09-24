# R6: training-label entry-lag check and the "any U in prior 3 years" rule (output: R6_misc_output.txt)
suppressMessages(library(data.table)); setwd("/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Overnight_2026-09-24/2_pivot_replication")
v<-readRDS("visits.rds"); cat("2024 visits entered on/after 2025-01-01:", v[year(d)==2024 & e>=as.IDate("2025-01-01"),.N], "\n")
cat("2023 visits entered in 2024:", v[year(d)==2023 & e>=as.IDate("2024-01-01"),.N], "\n")
p<-readRDS("panel.rds")[stage=="test"]; p[,yU:=fifelse(is.na(y),0L,y)]
cat("any-U-prior-3y rule: sites",p[u3>0,.N]," fails",p[u3>0,sum(yU)], " 20% frac yield", p[,{k<-ceiling(.2*.N); n1<-sum(u3>0); sum(yU*(u3>0))*min(1,k/n1)},by=P][,sum(V1)],"\n")
