require 'os'
require 'nn'
require 'rnn'
require 'optim'
require 'parallel'

nforks = 10

function genNbyK(n, k, a, b)
    out = torch.LongTensor(n, k)
    for i=1, n do
        for j = 1, k do
            out[i][j] = torch.random(a, b)
        end
    end
    return out
end

function worker()
    require 'sys'
    require 'torch'
    require 'math'

    function buildTokenCounts(summary, stopwordlist)
        local counts = {}
        for i=1, summary:size(1) do
            for j=1, summary:size(2) do
                if summary[i][j] > 0 then
                    local token = summary[i][j]
                    if counts[token] == nil then
                        counts[token] = 1
                    else
                        counts[token] = counts[token] + 1
                    end
                end
            end
        end
        return counts
    end
    function rougeScores(genSummary, refSummary)
        local genTotal = 0
        local refTotal = 0
        local intersection = 0
        -- Inserting the missing keys
        for k, genCount in pairs(genSummary) do
            if refSummary[k] == nil then
                refSummary[k] = 0
            end
        end
        for k, refCount in pairs(refSummary) do
            local genCount = genSummary[k]
            if genCount == nil then 
                genCount = 0 
            end
            intersection = intersection + math.min(refCount, genCount)
            refTotal = refTotal + refCount
            genTotal = genTotal + genCount
        end

        recall = intersection / refTotal
        prec = intersection / genTotal
        if refTotal == 0 then
            recall = 0
        end 
        if genTotal == 0 then
            prec = 0
        end
        -- tmp = {intersection, refTotal, genTotal}
        if recall > 0 or prec > 0 then
            f1 = (2 * recall * prec) / (recall + prec)
        else 
            f1 = 0
        end
        return recall, prec, f1
    end

    nforks = 10

    while true do
        m = parallel.yield() -- yield = allow parent to terminate me
        if m == 'break' then 
            break 
        end
        t = parallel.parent:receive()  -- receive data
        chunksize = math.floor(t.data:size(1) / nforks)
        start_index = chunksize * (parallel.id-1) + 1
        end_index = chunksize * parallel.id
        -- Prints the indices and shows that it's working
        -- print(parallel.id, start_index, end_index, t.data[{{start_index, end_index}}]:size(1))
        data_ss = t.data[{{start_index, end_index}}]

        perf = rougeScores(buildTokenCounts(data_ss), )
        parallel.parent:send(perf)
    end
end

function parent(input)
    parallel.nfork(nforks)
    parallel.children:exec(worker)
    send_var = {name='my variable', data=input} 

    parallel.children:join()
    parallel.children:send(send_var)
    replies = parallel.children:receive()
    parallel.children:join('break')
    print(replies)
end


xs = genNbyK(10, 5, 0, 5)
truexs = genNbyK(10, 5, 0, 5)

-- protected execution
ok, err = pcall(parent, xs)
if not ok then 
    print(err) 
end

parallel.close()
