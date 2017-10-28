import pickle
import dill
import pandas as pd
import numpy as np
from collections import Counter

import torch
import torch.autograd as autograd
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim

import torch
import torch.autograd as autograd
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from joblib import Parallel, delayed

def make_bow_vector(sentence, word_to_ix):
    vec = torch.zeros(len(word_to_ix))
    for token in sentence:
        vec[token] += 1
    return vec.view(1, -1)

def main():
	def make_bow_vector(sentence, word_to_ix): 
		vec = torch.zeros(len(word_to_ix))
		for token in sentence:
			vec[token] += 1
		return vec.view(1, -1)
	
	inputfile = "/home/francisco/GitHub/DQN-Event-Summarization/data/cnn_tokenized/cnn_data_corpus.csv"
	inputdict = "/home/francisco/GitHub/DQN-Event-Summarization/data/cnn_tokenized/cnn_total_corpus_smry.csv"
	
	qdf = pd.read_csv(inputfile)
	qdict = pd.read_csv(inputdict)

	queries = qdf['query_id']
	sentences = qdf[[x for x in qdf.columns if 'stokens_' in x]]

	true_summaries = {}
	for queryid, true_summary in zip(queries, qdf['tstokens']):
		true_summaries[queryid] = Counter([int(x) for x in true_summary.split(" ")])
	
	corpus_dict = dict(zip(qdict['id'].values, qdict['token'].values))
	
	sentence_list = []
	
	def tensorSentence(sentencevar):
		xs = torch.zeros(sentences.shape[0], len(corpus_dict))	
		for i, row in enumerate(sentences[sentencevar]):
			tokens = row.split(" ")
			
			if len(tokens) > 0:
				xs[i, :] = make_bow_vector([int(s) for s in tokens], corpus_dict)
		return xs
	
	sentence_list.append(tensorSentence('stokens_0'))
	sentence_list.append(tensorSentence('stokens_1'))
	
	print(len(sentence_list))
	
if __name__ == '__main__':
	main()
