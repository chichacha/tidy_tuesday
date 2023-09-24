#---------------- Libraries 
library(tidyverse)
library(janitor)
library(ggforce)
library(tidygraph)
library(ggraph)
library(tidytext)
library(lubridate)
library(gt)
library(gtExtras)


#---------------- Getting the Data 
# Option 1: tidytuesdayR package 
## install.packages("tidytuesdayR")

tuesdata <- tidytuesdayR::tt_load('2023-09-19')
names(tuesdata)
## OR
#tuesdata <- tidytuesdayR::tt_load(2023, week = 38)

cran <- tuesdata$cran_20230905 |>
  clean_names()
authors <- tuesdata$package_authors |> 
  clean_names()
nodes <- tuesdata$cran_graph_nodes |>
  clean_names()
edges <- tuesdata$cran_graph_edges |>
  clean_names()

# Option 2: Read directly from GitHub
# 
# cran_20230905 <- readr::read_csv('https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2023/2023-09-19/cran_20230905.csv')
# package_authors <- readr::read_csv('https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2023/2023-09-19/package_authors.csv')
# cran_graph_nodes <- readr::read_csv('https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2023/2023-09-19/cran_graph_nodes.csv')
# cran_graph_edges <- readr::read_csv('https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2023/2023-09-19/cran_graph_edges.csv')


#--------------- Getting Familiar with data
cran %>% skimr::skim()

### How come some packages appear multiple times?
cran %>% add_count(package) %>%
  filter(n>1) %>%
  arrange(desc(n), package) %>%
  DT::datatable()

cran_descr <- cran %>% group_by(package) %>%
  summarise(description=first(description),
            published=min(published,na.rm=T),
            title=first(title)) %>%
  ungroup() %>%
  mutate(package_ini = str_sub(package,1L,1L),
         is_ini_lower = str_to_lower(package_ini)==package_ini,
         pub_mo = month(published,label=T),
         pub_yr = year(published))

cran_descr %>% skimr::skim()

cran_descr %>% count(package_ini,sort=T)
cran_descr %>% count(ini=str_to_upper(package_ini),is_ini_lower) %>%
  pivot_wider(names_from=is_ini_lower, values_from=n) %>%
  adorn_totals(where=c("row","col")) %>%
  gt() %>%
  gt_theme_538() %>%
  gt_color_rows(is.numeric)

cran_descr %>%
  mutate(package_ini_u = str_to_upper(package_ini)) %>%
  mutate(mo=month(published,label=T)) %>%
  count(mo,package_ini_u) %>%
  ggplot(aes(x=package_ini_u,y=n)) +
  geom_col(aes(fill=mo)) +
  ggthemes::scale_fill_tableau("Hue Circle")

## package name starting with S is most popular, followed by R, M, C
## The least used package name starting with Y
  

cran_descr %>%
  ggplot(aes(x=published,y=fct_rev(str_to_upper(package_ini)))) +
  geom_point(aes(color=month(published, label=T)), shape="|") +
  theme_minimal(base_family="Roboto Condensed") +
  ggthemes::scale_color_tableau("Hue Circle") +
  facet_wrap(~is_ini_lower)

cran_descr %>% arrange(published)
## Earliest is 2008 September 8th pack


cran_descr_tidy <- cran_descr %>%
  tidytext::unnest_tokens(output="word", input="description") %>%
  anti_join(stop_words)

cran_descr_tidy %>% count(word,sort=T)  %>%
  wordcloud2::wordcloud2(rotateRatio=0)


### Important words by Initial of Package

cran_descr_tidy %>% 
  mutate(ini_u=str_to_upper(package_ini)) %>%
  count(word,ini_u) %>%
  bind_tf_idf(term="word", document="ini_u",n="n") %>%
  arrange(desc(tf_idf)) %>%
  group_by(ini_u) %>%
  mutate(rnk=row_number(desc(tf_idf)),
         total=sum(n)) %>%
  filter(rnk<=10) %>%
  ggplot(aes(x=rnk,y=n)) +
  geom_col(aes(fill=tf_idf), alpha=0.3) +
  geom_text(aes(y=0,label=word), hjust=0, family="Roboto Condensed") +
  coord_flip() +
  facet_wrap(~ini_u, scales="free") +
  scale_fill_viridis_c() +
  theme_minimal(base_family="Roboto Condensed") +
  scale_x_reverse()


cran_g <- tbl_graph(nodes=nodes,edges=edges)
cran_g

nodes %>% ggplot(aes(x=x,y=y)) +
  geom_point(aes(color=dist2hw,size=1/cc)) +
  coord_fixed() +
  scale_size_continuous(range=c(0.1,3)) +
  theme_void()

cran_g %>% ggraph(x=x,y=y) +
  geom_edge_bend0(edge_width=0.1, aes(alpha=1/weight)) +
  geom_node_point(aes(color=dist2hw),size=0.3) +
  scale_color_viridis_c(option="G") +
  coord_fixed()


cran %>% select(package,depends,imports) %>%
  mutate(depends=replace_na(depends,""),
         imports=replace_na(imports,"")) %>%
  mutate(relates=str_trim(str_c(depends,", ",imports))) %>%
  mutate(relates=str_split(relates,",")) %>%
  unnest(relates) %>%
  mutate(relates=str_trim(relates)) %>%
  filter(str_count(relates)>1) %>%
  filter(!str_detect(relates,"R (.+)")) %>%
  mutate(relates=str_trim(str_remove_all(relates,"\\(.+\\)"))) %>%
  count(relates,sort=T) -> cran_depends_rnk

cran_depends_rnk <- cran_depends_rnk %>%
  mutate(rnk=dense_rank(desc(n)))

cran %>% left_join(cran_depends_rnk %>% select(package=relates,rnk)) %>%
  relocate(package,rnk) %>%
  arrange(rnk) %>%
  filter(rnk<=50) %>%
  select(package,rnk,version,imports,depends,author,description) %>%
  gt()

cran %>% filter(str_detect(description,regex("(colour|color)", ignore_case=T))) %>%
  select(package,published,description) %>%
  gt()

cran %>% arrange(desc(published)) %>%
  select(package,published,description)

cran_descr %>%
  count(published,ini_u=str_to_upper(package_ini)) %>%
  group_by(ini_u) %>%
  mutate(cum_n=cumsum(n)) %>%
  ggplot(aes(x=published,y=cum_n)) +
  geom_line(aes(color=ini_u)) +
  scale_y_continuous(trans="log1p")

cran_descr %>% mutate(title_len=str_count(title)) %>%
  select(package,title_len,title,description) %>% arrange(title_len)

cran <- cran %>% mutate(url=str_glue("https://cran.r-project.org/web/packages/{package}"))

cran %>% count(language,sort=T)
cran %>% count(bug_reports,sort=T) %>% sample_n(20)
cran %>% count(type)

cran <- cran %>% mutate(bug_report_domain=urltools::domain(bug_reports))
cran %>% count(bug_report_domain,sort=T) %>%
  mutate(n=log(n)) %>%
  filter(!is.na(bug_report_domain)) %>% wordcloud2::wordcloud2()


cran %>% filter(!is.na(bug_report_domain)) %>%
  mutate(package_url = str_glue("<a href={url}>{package}</a>")) %>%
  group_by(bug_report_domain) %>%
  summarise(package=paste(package_url,collapse=", "),
            cnt=n()) %>%
  arrange(cnt) %>%
  gt() %>%
  fmt_markdown(package)
