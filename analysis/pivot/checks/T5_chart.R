# T5: one chart - Jan-Jun restroom failure rate 2012-2026, split into the two kinds of "U"
suppressMessages({library(data.table); library(ggplot2)})
t <- fread("h1_decomposition.csv")
l <- melt(t[, .(yr, `Failed with sub-ratings (condition problem found)`=fail_subs, `Failed with no sub-ratings (restroom not rated inside)`=fail_noSubs)], id.vars="yr")
l[, variable:=factor(variable, levels=rev(levels(factor(variable))))]
p <- ggplot(l, aes(factor(yr), value, fill=variable)) +
  geom_col(width=.62, colour="#fcfcfb", linewidth=.5) +
  geom_text(data=t, aes(factor(yr), fail, label=sprintf("%.1f%%", 100*fail)), inherit.aes=FALSE, vjust=-.5, size=3, colour="#52514e") +
  scale_fill_manual(values=c("#eb6834","#2a78d6"), name=NULL) +
  scale_y_continuous(labels=function(x) paste0(round(100*x),"%"), expand=expansion(mult=c(0,.08))) +
  labs(x=NULL, y="Share of rated inspections marked U",
       title="NYC Parks comfort stations: Jan–Jun inspection failure rate",
       subtitle="2026 is back at 2012–14 levels after a record low in 2022–24. Both kinds of failure at least doubled vs 2024.",
       caption="Source: NYC Parks PIP comfort-station inspections (mp8v-wjtf) joined to master (yg3y-7juh), Jan 1–Jun 28 each year; A/U only (N excluded).") +
  theme_minimal(base_size=11) +
  theme(panel.grid.major.x=element_blank(), panel.grid.minor=element_blank(), legend.position="top", legend.justification="left",
        plot.background=element_rect(fill="#fcfcfb", colour=NA), text=element_text(colour="#0b0b0b"),
        axis.text=element_text(colour="#52514e"), plot.caption=element_text(colour="#52514e", size=7.5, hjust=0),
        plot.title.position="plot", plot.caption.position="plot")
ggsave("h1_failure_2012_2026.png", p, width=9, height=5, dpi=200)
