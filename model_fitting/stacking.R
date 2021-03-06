# =================================================================================================================
# Generalized stacking

# from: http://blog.kaggle.com/2016/12/27/a-kagglers-guide-to-model-stacking-in-practice/
# =================================================================================================================

library(dplyr)
library(magrittr)
library(caret)
library(xgboost)
library(randomForest)

# ================================================================================================================
# load data
# dir <- file.path(getwd(),"data")
# train <- read.csv(file.path(dir, "train.csv"))
# 
# train <- train[, -1]
# train <- mutate_if(train, is.integer, as.numeric)
# 
# set.seed(444)

# creating training and test sets 
# train_index <- caret::createDataPartition(y = train$country_destination, p = 0.70, list = FALSE)
# training <- train[train_index, ]
# test <- train[-train_index, ]
# =================================================================================================================

# process:
#     1. fit models to training folds
#     2. predict on test fold (hold out one fold, and combine other folds to train)
#     3. store predictions as M1 or M2 in train_meta2
#     4. fit models to entire training data 
#     5. store predictions as M1 or M2 in test_meta 
#     6. fit xgboost to M1 and M2 of train_meta2, predict on M1, M2 of test_meta 

# =================================================================================================================
# setting up train_meta2 and test_meta
# =================================================================================================================

# over/undersampling training data 

sampled_list <- list()

# oversampling
# sampled_list[[1]] <- training %>% filter(country_destination == "AU") %>% sample_n(size = 1200, replace = TRUE)
# sampled_list[[2]] <- training %>% filter(country_destination == "CA") %>% sample_n(size = 3000, replace = TRUE)
# sampled_list[[3]] <- training %>% filter(country_destination == "DE") %>% sample_n(size = 2300, replace = TRUE)
# sampled_list[[4]] <- training %>% filter(country_destination == "NL") %>% sample_n(size = 2000, replace = TRUE)
# sampled_list[[5]] <- training %>% filter(country_destination == "PT") %>% sample_n(size = 1000, replace = TRUE)
# sampled_list[[6]] <- training %>% filter(country_destination == "ES") %>% sample_n(size = 5000, replace = TRUE)
# sampled_list[[7]] <- training %>% filter(country_destination == "GB") %>% sample_n(size = 5000, replace = TRUE)
# sampled_list[[8]] <- training %>% filter(country_destination == "IT") %>% sample_n(size = 6000, replace = TRUE)
# sampled_list[[11]] <- training %>% filter(country_destination == "FR") %>% sample_n(size = 10000, replace = TRUE)
# 
# # undersampling
# sampled_list[[9]] <- training %>% filter(country_destination == "NDF") %>% sample_n(size = 30000, replace = TRUE)
# sampled_list[[10]] <- training %>% filter(country_destination == "US") %>% sample_n(size = 15000, replace = TRUE)
# 
# # none
# # sampled_list[[11]] <- training %>% filter(country_destination == "FR") #%>% sample_n(size = 10000, replace = TRUE)
# sampled_list[[12]] <- training %>% filter(country_destination == "other")


# sampled_list[[1]] <- training %>% filter(country_destination == "AU") %>% sample_n(size = 3000, replace = TRUE)
# sampled_list[[2]] <- training %>% filter(country_destination == "CA") %>% sample_n(size = 3000, replace = TRUE)
# sampled_list[[3]] <- training %>% filter(country_destination == "DE") %>% sample_n(size = 3000, replace = TRUE)
# sampled_list[[4]] <- training %>% filter(country_destination == "NL") %>% sample_n(size = 3000, replace = TRUE)
# sampled_list[[5]] <- training %>% filter(country_destination == "PT") %>% sample_n(size = 3000, replace = TRUE)
# sampled_list[[6]] <- training %>% filter(country_destination == "ES") %>% sample_n(size = 3000, replace = TRUE)
# sampled_list[[7]] <- training %>% filter(country_destination == "GB") %>% sample_n(size = 3000, replace = TRUE)
# sampled_list[[8]] <- training %>% filter(country_destination == "IT") %>% sample_n(size = 3000, replace = TRUE)
# 
# # undersampling
# sampled_list[[9]] <- training %>% filter(country_destination == "NDF") %>% sample_n(size = 35000, replace = TRUE)
# sampled_list[[10]] <- training %>% filter(country_destination == "US") %>% sample_n(size = 20000, replace = TRUE)
# 
# # none
# sampled_list[[11]] <- training %>% filter(country_destination == "FR") #%>% sample_n(size = 10000, replace = TRUE)
# sampled_list[[12]] <- training %>% filter(country_destination == "other")
# 
# train_meta2 <- bind_rows(sampled_list)


# stacking with SMOTE data (smoted_train)
train_meta <- smoted_train
train_meta$class <- as.factor(train_meta$class)
colnames(train_meta)[which(colnames(train_meta) == "class")] <- "country_destination"
train_meta <- mutate_if(train_meta, is.integer, as.numeric)


# converting NA to -1 (xgb can't work with NA)
train_meta[ ,colnames(train_meta)[colSums(is.na(train_meta)) > 0]] <- -1
test[ ,colnames(test)[colSums(is.na(test)) > 0]] <- -1

# shuffling order of sampled_train_s
train_meta <- train_meta[sample(nrow(train_meta)), ] 

# partition training into 5 folds
train_meta$fold <- sample(c(1:5), size = nrow(train_meta), prob = rep(0.2, times = 5), replace = TRUE)

# =================================================================================================================

# use train_meta and test_meta only in this file 

# creating train_meta and test_meta, store predictions in M1, M2 
train_meta <- cbind(train_meta, M1 = 0, M2 = 0)
test_meta <- cbind(test, M1 = 0, M2 = 0) # test from over_undersampling.R


# =================================================================================================================
# fit xgboost 
# =================================================================================================================

# parameters for xgb
parameters <- list("objective" = "multi:softprob",
                   "num_class" = 12,
                   eta = 0.3, 
                   max_depth = 8, 
                   min_child_weight = 1, 
                   subsample = 0.8)
n_round <- 10


# function to fit xgboost, returns predictions on test set 
cv_xgboost <- function(train1, train2, train3, train4, test, data) { 
  
  # set up train and test data, include only features from imp_f_xg
  train <- data[which(data$fold == train1 |
                        data$fold == train2 |
                        data$fold == train3 | 
                        data$fold == train4), ] %>% select(imp_f_xgb, country_destination)
  
  test <- data[which(data$fold == test), ] %>% select(imp_f_xgb, country_destination)
  
  # convert train and test to Dmatrices
  train_m <- xgb.DMatrix(data = data.matrix(train %>% select(-country_destination)), 
                         label = as.numeric(train$country_destination) - 1)
  
  test_m <- xgb.DMatrix(data = data.matrix(test %>% select(-country_destination)),
                        label = as.numeric(test$country_destination) - 1)
  
  # fit xgboost 
  fit <- xgb.train(params = parameters, 
                   data = train_m, 
                   nrounds = n_round)
  
  # predict on test set 
  preds <- predict(fit, newdata = test_m)
  
  # convert predictions to df 
  preds_df <- as.data.frame(matrix(preds, 
                                   nrow = length(preds) / 12, 
                                   ncol = 12, 
                                   byrow = TRUE)) %>% mutate(label = as.numeric(test[,1]),
                                                             max_prob = max.col(., "last"))
  return(preds_df$max_prob)
  
  }

# apply function, store predictions in M1 column 
train_meta$M1[train_meta$fold == 1] <- cv_xgboost(train1 = 2, train2 = 3, train3 = 4, train4 = 5, test = 1)
train_meta$M1[train_meta$fold == 2] <- cv_xgboost(train1 = 3, train2 = 4, train3 = 5, train4 = 1, test = 2)
train_meta$M1[train_meta$fold == 3] <- cv_xgboost(train1 = 4, train2 = 5, train3 = 1, train4 = 2, test = 3)
train_meta$M1[train_meta$fold == 4] <- cv_xgboost(train1 = 5, train2 = 1, train3 = 2, train4 = 3, test = 4)
train_meta$M1[train_meta$fold == 5] <- cv_xgboost(train1 = 1, train2 = 2, train3 = 3, train4 = 4, test = 5)
beepr::beep()

# train_meta$M1 <- train_meta$M1 - 1
 
# =================================================================================================================
# fit random forest 
# =================================================================================================================

# function to fit rf on training data and predict on test
cv_rf <- function(train1, train2, train3, train4, test, data) {
  
  # set up train and test sets
  train <- data[which(data$fold == train1 |
                              data$fold == train2 |
                              data$fold == train3 | 
                              data$fold == train4), ] %>% select(imp_f_rf, country_destination)
  
  test <- data[which(data$fold == test), ] %>% select(imp_f_rf, country_destination)
  
  # fit model 
  rf_model <- randomForest(country_destination ~ ., 
                           data = train, 
                           ntree = 50,
                           do.trace = 10, 
                           type = "prob")
  
  # predict on test 
  pred <- predict(rf_model, newdata = test)
  
  return(pred)
  
}

# store predictions in M2 column 
train_meta$M2[train_meta$fold == 1] <- cv_rf(train1 = 2, train2 = 3, train3 = 4, train4 = 5, test = 1)
train_meta$M2[train_meta$fold == 2] <- cv_rf(train1 = 3, train2 = 4, train3 = 5, train4 = 1, test = 2)
train_meta$M2[train_meta$fold == 3] <- cv_rf(train1 = 4, train2 = 5, train3 = 1, train4 = 2, test = 3)
train_meta$M2[train_meta$fold == 4] <- cv_rf(train1 = 5, train2 = 1, train3 = 2, train4 = 3, test = 4)
train_meta$M2[train_meta$fold == 5] <- cv_rf(train1 = 1, train2 = 2, train3 = 3, train4 = 4, test = 5)
beepr::beep()

# train_meta$M2 <- train_meta$M2 - 1 # 84% accuracy 

# saving as csv
# write.csv(train_meta, file = "train_stacking.csv")

# =================================================================================================================
# fit each model to full training set, predict on test set, store as predictions in M1, M2
# =================================================================================================================

# xgboost

train_xgb <- train_meta %>% select(imp_f_xgb, country_destination)
                                   
test_xgb <- test_meta %>% select(imp_f_xgb, country_destination)

# set up training + test
full_train <- xgb.DMatrix(data = data.matrix(train_xgb %>% select(-country_destination)), 
                          label = as.numeric(train_xgb$country_destination) - 1)

full_test <- xgb.DMatrix(data = data.matrix(test_xgb %>% select(-country_destination)), 
                         label = as.numeric(test_xgb$country_destination) - 1)

# fit model 
xgb_full <- xgb.train(params = parameters, 
                      data = full_train, 
                      nrounds = n_round)

# predict
xgb_preds <- predict(xgb_full, newdata = full_test)

# store predictions as df 
preds_df <- as.data.frame(matrix(xgb_preds, nrow = length(xgb_preds) / 12, 
                                 ncol = 12, 
                                 byrow = TRUE)) %>% mutate(label = as.numeric(test_meta$country_destination),
                                                           max_prob = max.col(., "last"))
# checking accuracy
sum(preds_df$max_prob == preds_df$label) / nrow(preds_df) # 87.4% 
table(preds_df$max_prob, preds_df$label)

ndcg5(xgb_preds, full_test) #  0.9208434

# store predictions in column M1 of test meta 
test_meta$M1 <- preds_df$max_prob

# ---------------------------------------------------------------------------------------

# random forest 

train_meta_rf <- train_meta %>% select(imp_f_rf, country_destination)

rf_full <- randomForest(country_destination ~ ., 
                        data = train_meta_rf, 
                        ntree = 50, 
                        do.trace = 10, 
                        type = "prob")
beepr::beep()


# predictions (this achieves 98%??)
test_meta_rf <- test_meta %>% select(imp_f_rf, country_destination)

test_meta$M2 <- predict(rf_full, newdata = test_meta_rf) # 0.86

# =================================================================================================================
# stacking - using xgboost as stacker 
# =================================================================================================================

train_meta$M1 <- train_meta$M1 - 1
train_meta$M2 <- train_meta$M2 - 1
test_meta$M1 <- test_meta$M1 - 1
test_meta$M2 <- as.numeric(test_meta$M2) - 1


# set up training data 
stacked_train <- xgb.DMatrix(data = data.matrix(train_meta %>% select(M1, M2, age_clean, starts_with("firstbook"))), 
                             label = as.numeric(train_meta$country_destination) - 1)

# set up test
stacked_test <- xgb.DMatrix(data = data.matrix(test_meta %>% select(M1, M2, age_clean, starts_with("firstbook"))),
                            label = as.numeric(test_meta$country_destination) - 1)

# fit xgboost 
stacked_xgb <- xgb.train(params = parameters, 
                         data = stacked_train, 
                         nrounds = n_round)

# predict on test 
stacked_preds <- predict(stacked_xgb, newdata = stacked_test)

# convert to data frame
stacked_predsdf <- as.data.frame(matrix(stacked_preds, 
                                        nrow = length(stacked_preds) / 12, 
                                        ncol = 12, 
                                        byrow = TRUE)) %>% mutate(label = (getinfo(stacked_test, "label") + 1),
                                                                  max_prob = max.col(., "last"))

# accuracy - 87.6%
sum(stacked_predsdf$max_prob == stacked_predsdf$label) / length(stacked_predsdf$max_prob) 

# confusion matrix 
table(stacked_predsdf$max_prob, stacked_predsdf$label)

# ncdg metric 
ndcg5(stacked_preds, stacked_test) # 0.962







# ===============================================================================================
# ===============================================================================================
# stacking with regular training data 
# ===============================================================================================
# ===============================================================================================

train_meta2 <- training
train_meta2$class <- as.factor(train_meta2$class)
colnames(train_meta2)[which(colnames(train_meta2) == "class")] <- "country_destination"
train_meta2 <- mutate_if(train_meta2, is.integer, as.numeric)


# converting NA to -1 (xgb can't work with NA)
train_meta2[ ,colnames(train_meta2)[colSums(is.na(train_meta2)) > 0]] <- -1
test[ ,colnames(test)[colSums(is.na(test)) > 0]] <- -1

# shuffling order of sampled_train_s
train_meta2 <- train_meta2[sample(nrow(train_meta2)), ] 

# partition training into 5 folds
train_meta2$fold <- sample(c(1:5), size = nrow(train_meta2), prob = rep(0.2, times = 5), replace = TRUE)

# =================================================================================================================

# use train_meta2 and test_meta only in this file 

# creating train_meta2 and test_meta, store predictions in M1, M2 
train_meta2 <- cbind(train_meta2, M1 = 0, M2 = 0)
test_meta2 <- cbind(test, M1 = 0, M2 = 0) # test from over_undersampling.R


# =================================================================================================================
# fit xgboost 
# =================================================================================================================

# parameters for xgb
parameters <- list("objective" = "multi:softprob",
                   "num_class" = 12,
                   eta = 0.3, 
                   max_depth = 8, 
                   min_child_weight = 1, 
                   subsample = 0.8)
n_round <- 10


# function to fit xgboost, returns predictions on test set 
cv_xgboost <- function(train1, train2, train3, train4, test) { 
  
  # set up train and test data, include only features from imp_f_xgb
  train <- train_meta2[which(train_meta2$fold == train1 |
                              train_meta2$fold == train2 |
                              train_meta2$fold == train3 | 
                              train_meta2$fold == train4), ] %>% select(imp_f_xgb, country_destination)
  
  test <- train_meta2[which(train_meta2$fold == test), ] %>% select(imp_f_xgb, country_destination)
  
  # convert train and test to Dmatrices
  train_m <- xgb.DMatrix(data = data.matrix(train %>% select(-country_destination)), 
                         label = as.numeric(train$country_destination) - 1)
  
  test_m <- xgb.DMatrix(data = data.matrix(test %>% select(-country_destination)),
                        label = as.numeric(test$country_destination) - 1)
  
  # fit xgboost 
  fit <- xgb.train(params = parameters, 
                   data = train_m, 
                   nrounds = n_round)
  
  # predict on test set 
  preds <- predict(fit, newdata = test_m)
  
  # convert predictions to df 
  preds_df <- as.data.frame(matrix(preds, 
                                   nrow = length(preds) / 12, 
                                   ncol = 12, 
                                   byrow = TRUE)) %>% mutate(label = as.numeric(test[,1]),
                                                             max_prob = max.col(., "last"))
  return(preds_df$max_prob)
  
}

# apply function, store predictions in M1 column 
train_meta2$M1[train_meta2$fold == 1] <- cv_xgboost(train1 = 2, train2 = 3, train3 = 4, train4 = 5, test = 1)
train_meta2$M1[train_meta2$fold == 2] <- cv_xgboost(train1 = 3, train2 = 4, train3 = 5, train4 = 1, test = 2)
train_meta2$M1[train_meta2$fold == 3] <- cv_xgboost(train1 = 4, train2 = 5, train3 = 1, train4 = 2, test = 3)
train_meta2$M1[train_meta2$fold == 4] <- cv_xgboost(train1 = 5, train2 = 1, train3 = 2, train4 = 3, test = 4)
train_meta2$M1[train_meta2$fold == 5] <- cv_xgboost(train1 = 1, train2 = 2, train3 = 3, train4 = 4, test = 5)
beepr::beep()

# train_meta2$M1 <- train_meta2$M1 - 1

# =================================================================================================================
# fit random forest 
# =================================================================================================================

# function to fit rf on training data and predict on test
cv_rf <- function(train1, train2, train3, train4, test) {
  
  # set up train and test sets
  train <- train_meta2[which(train_meta2$fold == train1 |
                              train_meta2$fold == train2 |
                              train_meta2$fold == train3 | 
                              train_meta2$fold == train4), ] %>% select(imp_f_rf, country_destination)
  
  test <- train_meta2[which(train_meta2$fold == test), ] %>% select(imp_f_rf, country_destination)
  
  # fit model 
  rf_model <- randomForest(country_destination ~ ., 
                           data = train, 
                           ntree = 50,
                           do.trace = 10, 
                           type = "prob")
  
  # predict on test 
  pred <- predict(rf_model, newdata = test)
  
  return(pred)
  
}

# store predictions in M2 column 
train_meta2$M2[train_meta2$fold == 1] <- cv_rf(train1 = 2, train2 = 3, train3 = 4, train4 = 5, test = 1)
train_meta2$M2[train_meta2$fold == 2] <- cv_rf(train1 = 3, train2 = 4, train3 = 5, train4 = 1, test = 2)
train_meta2$M2[train_meta2$fold == 3] <- cv_rf(train1 = 4, train2 = 5, train3 = 1, train4 = 2, test = 3)
train_meta2$M2[train_meta2$fold == 4] <- cv_rf(train1 = 5, train2 = 1, train3 = 2, train4 = 3, test = 4)
train_meta2$M2[train_meta2$fold == 5] <- cv_rf(train1 = 1, train2 = 2, train3 = 3, train4 = 4, test = 5)
beepr::beep()

# train_meta2$M2 <- train_meta2$M2 - 1 # 84% accuracy 

# saving as csv
# write.csv(train_meta2, file = "train_stacking.csv")

# =================================================================================================================
# fit each model to full training set, predict on test set, store as predictions in M1, M2
# =================================================================================================================

# xgboost

train_xgb2 <- train_meta2 %>% select(imp_f_xgb, country_destination)

test_xgb2 <- test_meta2 %>% select(imp_f_xgb, country_destination)

# set up training + test
full_train2 <- xgb.DMatrix(data = data.matrix(train_xgb2 %>% select(-country_destination)), 
                          label = as.numeric(train_xgb2$country_destination) - 1)

full_test2 <- xgb.DMatrix(data = data.matrix(test_xgb2 %>% select(-country_destination)), 
                         label = as.numeric(test_xgb2$country_destination) - 1)

# fit model 
xgb_full2 <- xgb.train(params = parameters, 
                      data = full_train2, 
                      nrounds = n_round)

# predict
xgb_preds2 <- predict(xgb_full2, newdata = full_test2)

# store predictions as df 
preds_df2 <- as.data.frame(matrix(xgb_preds2, nrow = length(xgb_preds2) / 12, 
                                 ncol = 12, 
                                 byrow = TRUE)) %>% mutate(label = as.numeric(test_meta2$country_destination),
                                                           max_prob = max.col(., "last"))
# checking accuracy
sum(preds_df2$max_prob == preds_df2$label) / nrow(preds_df2) # 87.4% 
table(preds_df2$max_prob, preds_df2$label)

# ndcg5(xgb_preds, full_test) #  0.9208434

# store predictions in column M1 of test meta 
test_meta2$M1 <- preds_df$max_prob

# ---------------------------------------------------------------------------------------

# random forest 

train_meta2_rf <- train_meta2 %>% select(imp_f_rf, country_destination)

rf_full2 <- randomForest(country_destination ~ ., 
                        data = train_meta2_rf, 
                        ntree = 50, 
                        do.trace = 10, 
                        type = "prob")
beepr::beep()


# predictions (this achieves 98%??)
test_meta2_rf <- test_meta2 %>% select(imp_f_rf, country_destination)

test_meta2$M2 <- predict(rf_full, newdata = test_meta2_rf) # 0.86

# =================================================================================================================
# stacking - using xgboost as stacker 
# =================================================================================================================

train_meta2$M1 <- train_meta2$M1 - 1
train_meta2$M2 <- train_meta2$M2 - 1
test_meta2$M1 <- test_meta2$M1 - 1
test_meta2$M2 <- as.numeric(test_meta2$M2) - 1


# set up training data 
stacked_train2 <- xgb.DMatrix(data = data.matrix(train_meta2 %>% select(M1, M2)), 
                             label = as.numeric(train_meta2$country_destination) - 1)

# set up test
stacked_test2 <- xgb.DMatrix(data = data.matrix(test_meta2 %>% select(M1, M2)),
                            label = as.numeric(test_meta2$country_destination) - 1)

# fit xgboost 
stacked_xgb2 <- xgb.train(params = parameters, 
                         data = stacked_train2, 
                         nrounds = n_round)

# predict on test 
stacked_preds2 <- predict(stacked_xgb2, newdata = stacked_test2)

# convert to data frame
stacked_predsdf2 <- as.data.frame(matrix(stacked_preds2, 
                                        nrow = length(stacked_preds2) / 12, 
                                        ncol = 12, 
                                        byrow = TRUE)) %>% mutate(label = (getinfo(stacked_test2, "label") + 1),
                                                                  max_prob = max.col(., "last"))

# accuracy - 87.6%
sum(stacked_predsdf2$max_prob == stacked_predsdf2$label) / length(stacked_predsdf2$max_prob) 

# confusion matrix 
table(stacked_predsdf2$max_prob, stacked_predsdf2$label)

# ncdg metric 
# ndcg5(stacked_preds, stacked_test) # 0.962



