require 'csvigo'

dofile("Code/utils.lua")

function readCNN(input_path, inputfile, idx)
    inputfile = string.format('cnn_data_sentence_%02d', idx)

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
    print(string.format("data %i loaded and tokenized...", idx))

    local q_x = torch.Tensor(padZeros(qtokens, maxq))
    local s_x = torch.Tensor(padZeros(stokens, maxs))
    local ts_x = torch.Tensor(padZeros(tstokens, maxts))

    torch.save(outputpath .. string.format("qtokens_sid_%i.dat", idx), q_x)
    torch.save(outputpath .. string.format("stokens_sid_%i.dat", idx), s_x)
    torch.save(outputpath .. string.format("tstokens_sid_%i.dat", idx), ts_x)
    print("...data exported to torch datafiles")
end

input_path = '/home/francisco/GitHub/DQN-Event-Summarization/data/cnn_tokenized/'
outputpath = "/home/francisco/GitHub/DQN-Event-Summarization/data/training/"

for i=0, 124 do 
    readCNN(input_path, inputfile, i)
end