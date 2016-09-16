import os
import re
import sys
import pickle
import csv
import pandas as pd
from gensim import corpora
from collections import defaultdict    

def BuildIndexFiles(infile_list):
    """
    :type  infile_list:  list
    :param infile_list:  List of file names to import
    """
    reload(sys)
    sys.setdefaultencoding('utf-8')
    all_tokens = []
    frequency = defaultdict(int)
    for idx, infilename in enumerate(infile_list):
        print('Loading %s %i of %i' % (infilename, idx, len(infile_list)) )

        df = pd.read_csv(infilename, sep='\t', encoding='latin-1')
        df['text'] = df['text'].str.replace('[^A-Za-z0-9]+', ' ').str.strip()
        texts = [ t.split(" ") for t in df['text'] ]

        for text in texts:
            for token in text:
                frequency[token] += 1
        texts = [ [token for token in text ]  for text in texts]
        # Collecting all the list of tokens
        all_tokens.append(texts)

    texts = sum(all_tokens, [])

    # Getting the dictionary with token info
    dictionary = corpora.Dictionary(texts)
    # Mapping to numeric list
    word2idx = dictionary.token2id
    dictionary.id2token = {v:k for k,v in dictionary.token2id.items()}
    idx2word = dictionary.id2token
    
    # Exporting the dictionaries
    print("Exporting word to index and dictionary to word indices")
    output = open('./0-output/LSTMDQN_Dic_token2id.pkl', 'ab+')
    pickle.dump(word2idx, output)
    output.close()

    output = open('./0-output/LSTMDQN_Dic_id2token.pkl', 'ab+')
    pickle.dump(idx2word, output)
    output.close()
    
    # Merging the dictionaries toa pandas data frame with summary info
    odf0 = pd.DataFrame.from_dict(dictionary.dfs, orient='index').reset_index()
    odf1 = pd.DataFrame.from_dict(word2idx, orient='index').reset_index()

    odf0.columns = ['id', 'frequency']
    odf1.columns = ['token', 'id']
    # Merge by token id
    odf = pd.merge(left=odf0, right=odf1, on='id')
    odf = odf[['id','token', 'frequency']]
    # Exporting data
    odf.to_csv('./0-output/total_corpus_smry.csv')
    
    return dictionary
    
def TokenizeData(infile_list, outfile_list, word2idx):
    """
    :type  infile_list:  list
    :param infile_list:  List of file names to import

    :type  outfile_list: list
    :param outfile_list: List of file names to export, without the '.csv'

    :type  word2idx:     dic
    :param word2idx:     Dictionary of token 2 ids
    """

    for idx, (infilename, outfilename) in enumerate(zip(infile_list, outfile_list)):
        df = pd.read_csv(infilename, sep='\t', encoding='latin-1')
        df['text'] = df['text'].str.replace('[^A-Za-z0-9]+', ' ').str.strip()
        texts = [ t.split(" ") for t in df['text'] ]

        frequency = defaultdict(int)
        for text in texts:
            for token in text:
                frequency[token] += 1
        texts = [ [token for token in text ]  for text in texts]
        
        text_numindex = [ [word2idx[i] for i in t] for t in texts]
        # Exporting files
        print('...file export to %s.csv' % outfilename)

        with open(outfilename+'_numtext.csv', 'wb') as csvfile:
            data = csv.writer(csvfile, delimiter=' ', quotechar='|', quoting=csv.QUOTE_MINIMAL)
            data.writerow(['Text'])
            data.writerows(text_numindex)

        csvfile.close()
    print('...Exporting of tokenized data complete')

if __name__ == '__main__':

    os.chdir('/Users/franciscojavierarceo/GitHub/DeepNLPQLearning/DO_NOT_UPLOAD_THIS_DATA/corpus-data/')

    infilelist = [
            './2012_aurora_shooting.tsv.gz', 
            './2012_pakistan_garment_factory_fires.tsv.gz',
            './hurricane_sandy.tsv.gz',
            './wisconsin_sikh_temple_shooting.tsv.gz'
    ]
    outfilelist = [
            './0-output/2012_aurora_shooting',
            './0-output/2012_pakistan_garment_factory_fires',
            './0-output/hurricane_sandy',
            './0-output/wisconsin_sikh_temple_shooting'
    ]

    mycorpora = BuildIndexFiles(infilelist)
    
    TokenizeData(infilelist, outfilelist, word2idx=mycorpora.token2id)

    print("----- END ------")