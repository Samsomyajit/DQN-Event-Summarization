require 'csvigo'

dofile("Code/utils.lua")
dofile("Code/utilsNN.lua")


function readCNN(input_path, inputfile, idx)
    inputfile = string.format('cnn_data_sentence_%02d.csv', idx)

    mydata =  csvigo.load({path = input_path .. inputfile .. '.csv', mode = "large", verbose = false})
    local qtokens, stokens, tstokens = {}, {}, {}
    local maxq, maxs, maxts = 0, 0, 0

    for i, row in pairs(mydata) do
        if i > 1 and row ~= nil then
            qtokens[i-1] = row[1]:split(" ")
            stokens[i-1] = row[2]:split(" ")
            tstokens[i-1] = row[3]:split(" ")
            maxq = math.max(maxq, #qtokens[i-1])
            maxs = math.max(maxs, #stokens[i-1])
            maxts = math.max(maxts, #tstokens[i-1])
        end
    end

    q_x = torch.Tensor(padZeros(qtokens, maxq))
    s_x = torch.Tensor(padZeros(stokens, maxs))
    ts_x = torch.Tensor(padZeros(tstokens, maxts))

    qfile = string.format("query_tokens_sid_%i.dat", idx)
    sfile = string.format("sentence_tokens_sid_%i.dat", idx)
    tsfile = string.format("truesummary_tokens_sid_%i.dat", idx)

    torch.save(outputpath .. qfile, q_x)
    torch.save(outputpath .. sfile, s_x)
    torch.save(outputpath .. tsfile, ts_x)
end

input_path = '/home/francisco/GitHub/DQN-Event-Summarization/data/cnn_tokenized/'
outputpath = "/home/francisco/GitHub/DQN-Event-Summarization/data/training/"

readCNN(input_path, inputfile, 0)