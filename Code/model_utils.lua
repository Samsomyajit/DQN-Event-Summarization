function score_model(opt_action, sentence_xs, input_nuggets, thresh, skip_rate, metric)
    --- Scores the model given the list of optimal actions, input sentences, and nuggets
        --- Note: we calculate *change* in rouge from time t-1 to t for each sentence
        --- The skip_rate controls this delta calculation
            --- skip_rate == 0 turns skip_rate off ==> always updates the lag 
                --- means we are computing s_t - s_{t-1}
            --- skip_rate >= 1 turns skip_rate always ==> never updates the lag
                --- means we are computing s_t - s_{t_0} and s_{t_0} == 0 ==> s_t
    local s_t1 = 0.
    local scores = {}
    if metric=='f1' then
        eval_func = rougeF1
    elseif metric=='recall' then
        eval_func = rougeRecall
    elseif metric=='precision' then
        eval_func = rougePrecision
    end
    for i=1, #opt_action do
        local curr_summary= buildPredSummary(geti_n(opt_action, 1, i), 
                                           geti_n(sentence_xs, 1, i),  nil)

        scores[i] = threshold(eval_func({curr_summary[i]}, input_nuggets ) - s_t1, thresh)
        s_t1 = scores[i]
        --- Skip rate controls how often we skip updating the lag
        --- e.g., if skip_rate = 0.25 <= [0, 1] ==> update lag 75% of the time
        if skip_rate > 0 then 
            if skip_rate <= torch.rand(1)[1] then
                s_t1 = scores[i] + s_t1
            end 
        else 
            s_t1 = scores[i] + s_t1
        end
    end
    return scores
end

function build_bowmlp(nn_vocab_module, edim)
    local model = nn.Sequential()
    :add(nn_vocab_module)           -- returns a (sequence-length x batch-size x edim) tensor
    :add(nn.Sum(1, edim, true))     -- splits into a sequence-length table with (batch-size x edim) entries
    :add(nn.Linear(edim, edim))     -- map last state to a score for classification
    -- :add(nn.ReLU())
    -- :add(nn.Tanh())                 --     :add(nn.ReLU()) <- this one did worse
   return model
end

function build_lstm(nn_vocab_module, edim)
    local model = nn.Sequential()
    :add(nn_vocab_module)            -- returns a (sequence-length x batch-size x edim) tensor
    :add(nn.SplitTable(1, edim))     -- splits into a sequence-length table with (batch-size x edim) entries
    :add(nn.Sequencer(nn.LSTM(edim, edim)))
    :add(nn.SelectTable(-1))            -- selects last state of the LSTM
    :add(nn.Linear(edim, edim))         -- map last state to a score for classification
    -- :add(nn.ReLU())
    -- :add(nn.Tanh())                     --     :add(nn.ReLU()) <- this one did worse
   return model
end

function build_model(model, vocab_size, embed_dim, use_cuda)
    local nn_vocab = nn.LookupTableMaskZero(vocab_size, embed_dim)
    if model == 'bow' then
        print("Running BOW model")
        mod1 = build_bowmlp(nn_vocab, embed_dim)
    end
    if model == 'lstm' then         
        print("Running LSTM model")
        mod1 = build_lstm(nn_vocab, embed_dim)
    end

    mod2 = mod1:clone()         --- Cloning the first model to share the weights
    mod3 = mod1:clone()         --- across the different inputs

    local ParallelModel = nn.ParallelTable()
    :add(mod1)                  --- Adding in the parts of the model
    :add(mod2)                  --- for each of the 3 inputs
    :add(mod3)                  --- i.e., sentence, summary, query

    local FinalMLP = nn.Sequential()
    :add(ParallelModel)         --- Adding in the components
    :add(nn.JoinTable(2))       --- Joining the components back together
    :add(nn.Linear(embed_dim * 3, 2) )      --- Adding linear layer to output 2 units
    :add(nn.Max(2) )            --- Max over the 2 units (action) dimension
    -- :add(nn.Tanh())             --- Adding a non-linearity

    if use_cuda then
        return FinalMLP:cuda()
    else
        return FinalMLP
    end
end


function BuildTensors(actions, sentences, queries, sindex, K, J)
    local tmp_actions = geti_n(actions, 1, sindex)
    local tmp_sentences = geti_n(sentences, 1, sindex)
    local summaries = buildCurrentSummary(tmp_actions, tmp_sentences, K * J)
    -- Building the tensors         
    local query = LongTensor(padZeros({queries}, 5) ):t()
    local sentence = LongTensor(padZeros({sentences[sindex]}, K) ):t()
    local summary =  LongTensor(padZeros({summaries[sindex]}, K) ):t()
    return summary, sentence, query
end
--- To do list:
    --- 1. RMS prop in optim package
            -- NOT DONE

function iterateModelQueries(input_path, query_file, batch_size, nepochs, inputs, 
                            nn_model, crit, thresh, embed_dim, epsilon, delta, 
                            base_explore_rate, print_every,
                            learning_rate, J_sentences, K_tokens, use_cuda,
                            skiprate, emetric, export, gamma)
    --- This function iterates over the epochs, queries, and sentences to learn the model
    if use_cuda then
        Tensor = torch.CudaTensor
        LongTensor = torch.CudaLongTensor
        crit = crit:cuda()
        print("...running on GPU")
    else
        torch.setnumthreads(8)
        Tensor = torch.Tensor
        LongTensor = torch.LongTensor
        print("...running on CPU")
    end

    print_string = string.format(
        "training model with metric = %s, learning rate = %.3f, K = %i, J = %i, threshold = %.3f, embedding size = %i",
                emetric, learning_rate, K_tokens, J_sentences, thresh, embed_dim, batch_size
                )

    print(print_string)

    vocab_size = 0
    maxseqlen = 0
    maxseqlenq = getMaxseq(query_file)

    action_query_list = {}
    yrouge_query_list = {}
    pred_query_list = {}

    --- Initializing query book-keeping 
    for query_id = 1, #inputs do
        input_fn = inputs[query_id]['inputs']
        nugget_fn = inputs[query_id]['nuggets']

        input_file = csvigo.load({path = input_path .. input_fn, mode = "large", verbose = false})
        nugget_file = csvigo.load({path = input_path .. nugget_fn, mode = "large", verbose = false})
        input_file = geti_n(input_file, 2, #input_file) 
        nugget_file = geti_n(nugget_file, 2, #nugget_file) 

        vocab_sized = getVocabSize(input_file)
        vocab_sizeq = getVocabSize(query_file)
        vocab_size = math.max(vocab_size, vocab_sized, vocab_sizeq)

        maxseqlend = getMaxseq(input_file)
        maxseqlen = math.max(maxseqlen, maxseqlenq, maxseqlend)
        action_list = torch.totable(torch.round(torch.rand(#input_file)))

        --- initialize the query specific lists
        action_query_list[query_id] = action_list
        yrouge_query_list[query_id] = torch.totable(torch.rand(#input_file))     --- Actual
        pred_query_list[query_id] = torch.totable(torch.zeros(#input_file))     --- Predicted
    end

    --- Specify model
    model  = build_model(nn_model, vocab_size, embed_dim, use_cuda)

    --- This is the main training function
    for epoch=0, nepochs, 1 do
        --- Looping over each bach of sentences for a given query
        for query_id = 1, #inputs do
            --- Grabbing all of the input data
            qs = inputs[query_id]['query']
            input_file = csvigo.load({path = input_path .. inputs[query_id]['inputs'], mode = "large", verbose = false})
            nugget_file = csvigo.load({path = input_path .. inputs[query_id]['nuggets'], mode = "large", verbose = false})
            
            --- Dropping the headers (which is the 1st row)
            input_file = geti_n(input_file, 2, #input_file) 
            nugget_file = geti_n(nugget_file, 2, #nugget_file) 
            
            --- Building table of indices for 
                -- first K_tokens of the input sentences
                -- and all tokens of the nuggets
            nuggets = buildTermDocumentTable(nugget_file, nil)
            xtdm  = buildTermDocumentTable(input_file, K_tokens)

            --- Extracting the query specific actions, labels, and predictions
            action_list = action_query_list[query_id]
            yrouge = yrouge_query_list[query_id] 
            preds = pred_query_list[query_id]
            
            --- Forward pass
            for minibatch = 1, #xtdm do
                --- Notice that the actionlist is optimized at after each iteration
                --- Building the input data
                summary, sentence, query = BuildTensors(action_list, xtdm, qs, minibatch, 
                                                        K_tokens, J_sentences)

                --- Retrieve intermediate optimal action in model.get(3).output
                local pred_rouge = model:forward({sentence, summary, query})   
                local pred_actions = torch.totable(model:get(3).output)     -- outputs the actions
                
                --- Epsilon greedy strategy
                if torch.rand(1)[1] < epsilon then 
                    opt_action = torch.round(torch.rand(1))[1]
                else 
                    --- Notice that pred_actions gives us our optimal action by returning
                    ---  E[rouge | Skip]  > E[rouge | Select ] then skip {0} else select {1}
                    opt_action = (pred_actions[1][1] > pred_actions[1][2]) and 0 or 1
                end

                -- Updating book-keeping tables at sentence level
                if minibatch < 3 then
                    x = string.format(
                        "pred rougue = %.8f, action0 = %.8f, action1 = %.8f, optaction = %i",
                            pred_rouge[1], pred_actions[1][1], pred_actions[1][2], opt_action
                            )
                    -- print(xtdm[minibatch], unpackZeros(summaries[minibatch]))
                end
                preds[minibatch] = pred_rouge[1]
                action_list[minibatch] = opt_action
            end --- ends the sentence level loop
            
            if export then 
                local pfile = io.open(string.format("plotdata/%s/%i_preds.txt", nn_model, epoch), 'w')
                local yfile = io.open(string.format("plotdata/%s/%i_actual.txt", nn_model, epoch), 'w')
                for i=1,#preds do
                    pfile:write(string.format("%.6f\n", preds[i] ) )
                    yfile:write(string.format("%.6f\n", yrouge[i] ) )
                end
                pfile:close()
                yfile:close()
            end 
            --- Note setting the skip_rate = 0 means no random skipping of delta calculation
            yrouge = score_model(action_list, 
                            xtdm,
                            nuggets,
                            thresh, 
                            skiprate, 
                            emetric)

            --- Updating book-keeping tables at query level
            pred_query_list[query_id] = preds
            yrouge_query_list[query_id] = yrouge
            action_query_list[query_id] = action_list

            --- Rerunning the scoring on the full data and rescoring cumulatively
            --- Execute policy and evaluation based on our E[rouge] after all of the minibatches
            predsummary = buildPredSummary(action_list, xtdm, nil)
            predsummary = predsummary[#predsummary]

            rscore = rougeRecall({predsummary}, nuggets)
            pscore = rougePrecision({predsummary}, nuggets)
            fscore = rougeF1({predsummary}, nuggets)

            --- creating randomly sampled query and input indices
            local qindices = {}
            local xindices = {}
            for i=1, batch_size do
                qindices[i] = math.random(1, #inputs)
                xindices[i] = math.random(1, #xtdm)
            end
            --- Building summaries on full set of input data then sampling after
            --- Need to do summaries first b/c if you build after sampling 
            --- you'll get incorrect summaries, also need to padZeros for empty summaries
            local summaries = padZeros(buildCurrentSummary(action_list, xtdm, 
                                        K_tokens * J_sentences), 
                                        K_tokens * J_sentences)
            loss = 0.
            --- Backward pass
            for i= 1, batch_size do
                sentence = LongTensor(padZeros( {xtdm[xindices[i]]}, K_tokens) ):t()
                summary = LongTensor({summaries[xindices[i]]}):t()
                query = LongTensor(padZeros({qs}, 5)):t()
                pred_rouge = Tensor({preds[xindices[i]]})
                --- Line 23 in algorithm
                if (xindices[i]) < #xtdm then
                    labels = Tensor({yrouge[xindices[i]] + gamma * yrouge[xindices[i] + 1] })
                else 
                    labels = Tensor({yrouge[xindices[i]]})
                end
                err = crit:forward(pred_rouge, labels)
                loss = loss + err
                if i < 3 then
                    print(string.format("loss = %.6f; actual = %.6f; predicted = %.6f predicted_t-1 = %.6f", err, labels[1], preds[xindices[i]], preds[xindices[i] + 1]  ))
                    print(pred_rouge)
                end
                --- Backprop model 
                local grads = crit:backward(pred_rouge, labels)
                model:zeroGradParameters()
                --- For some reason runnign the :forward() makes the backward pass work
                --- spent a lot of time trying to debug why :backward() didn't work without it
                --- but I couldn't figure it out, then I tried this and it works...seems wrong.
                --- I'll ask Chris about this and see what he thinks
                local tmp = model:forward({sentence, summary, query})
                model:backward({sentence, summary, query}, grads)
                model:updateParameters(learning_rate)
            end
            -- print(geti_n(preds, 1,5))
            -- print(geti_n(yrouge, 1,5))
            if (epoch % print_every)==0 then
                print(string.format('there are %i sentences with 0 out of 1000', c))
                pmin = math.min(table.unpack(preds))
                pmax = math.max(table.unpack(preds))
                pmean = sumTable(preds) / #yrouge
                ymin = math.min(table.unpack(yrouge))
                ymax = math.max(table.unpack(yrouge))
                ymean = sumTable(yrouge) / #yrouge
                print(string.format("Predicted {min = %.6f, mean = %.6f, max = %.6f}", pmin, pmean, pmax))
                print(string.format("Actual    {min = %.6f, mean = %.6f, max = %.6f}", ymin, ymean, ymax))
                perf_string = string.format(
                    "Epoch %i, loss  = %.3f, epsilon = %.3f, sum(y)/len(y) = %i/%i, {Recall = %.6f, Precision = %.6f, F1 = %.6f}, query = %s", 
                    epoch, loss, epsilon, sumTable(action_list), #action_list, rscore, pscore, fscore, inputs[query_id]['query_name']
                    )
                print(perf_string)
            end
        end -- ends the query level loop
        --- Reducing epsilon-greedy search linearly and setting it to the base rate
        if (epsilon - delta) <= base_explore_rate then
            epsilon = base_explore_rate
        else 
            epsilon = epsilon - delta
        end
    end -- ends the epoch level loop
    if export_ then
        print(string.format("Exporting density of predictions to ./density.gif"))
        os.execute(string.format("python make_density_gif.py %i %s", nepochs, nn_model))
    end
    return model, summary_query_list, action_query_list, yrouge_query_list
end