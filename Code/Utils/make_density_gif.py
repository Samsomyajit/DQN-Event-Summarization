import os
import sys
import imageio
import numpy as np
import pandas as pd
from matplotlib import pyplot as plt
import matplotlib.colors as mcolors


def make_colormap(seq):
    """Return a LinearSegmentedColormap
    seq: a sequence of floats and RGB-tuples. The floats should be increasing
    and in the interval (0,1).
    """
    seq = [(None,) * 3, 0.0] + list(seq) + [1.0, (None,) * 3]
    cdict = {'red': [], 'green': [], 'blue': []}
    for i, item in enumerate(seq):
        if isinstance(item, float):
            r1, g1, b1 = seq[i - 1]
            r2, g2, b2 = seq[i + 1]
            cdict['red'].append([item, r1, r2])
            cdict['green'].append([item, g1, g2])
            cdict['blue'].append([item, b1, b2])
    return mcolors.LinearSegmentedColormap('CustomMap', cdict)


def buildCDF(df, var):
    cdf = pd.DataFrame(df[var].value_counts())
    cdf = cdf.reset_index(drop=False)
    cdf.columns = [var, 'count']
    cdf['percent'] = cdf['count'] / cdf['count'].sum()
    cdf = cdf.sort_values(by=var)
    cdf['cumpercent'] = cdf['percent'].cumsum()
    return cdf

def main(nepochs, model, metric):
    if type(nepochs) == str:
        nepochs = int(nepochs)
    
    pdf = pd.read_csv('./Code/Performance/Simulation/%s_%s_perf.txt' % (model, metric) , sep=';')
    md = {"f1": "rougeF1", "recall": "rougeRecall", "precision": "rougePrecision"}
    emetric = md[metric]
    c = mcolors.ColorConverter().to_rgb
    grn = 'limegreen'
    rvb = make_colormap([c(grn), c('white'), 0.1, c(grn), c('white'), 0.9, c('white')])
    # Pulling in the images that were exported
    ofile_names = [('./Code/plotdata/%s/1/%i_epoch.txt' % (model, x) ) for x in range(nepochs) ] 
    for (ofile, epoch) in zip(ofile_names, range(nepochs)):
        # Loading data sets and concatenating them
        odf = pd.read_csv(ofile, sep=';')
        if epoch  == 0:
            llow  = min(odf['actual'].min(), odf['predSelect'].min(), odf['predSkip'].min())
            lhigh = max(odf['actual'].max(), odf['predSelect'].max(), odf['predSkip'].max())

        llow  = min(llow, odf['actual'].min(), odf['predSelect'].min(), odf['predSkip'].min())
        lhigh = max(lhigh, odf['actual'].max(), odf['predSelect'].max(), odf['predSkip'].max())

    for (ofile, epoch) in zip(ofile_names, range(nepochs)):
        # Loading data sets and concatenating them
        # Two subplots, the axes array is 1-d
        rouge = pdf[pdf['epoch']==epoch][emetric].tolist()[0]
        odf = pd.read_csv(ofile, sep=';')
        odf['predOptimal'] = odf[['predSelect','predSkip']].max(axis=1)
        nsel  = odf['Select'].sum()
        nskip = odf['Skip'].sum()
        den =  float(nsel+nskip)
        cdfp = buildCDF(odf, 'predOptimal')
        cdfa = buildCDF(odf, 'actual')
        f, axarr = plt.subplots(1, 2, figsize=(16,8))
        axarr[0].imshow(odf[['Skip', 'Select']], cmap=rvb, interpolation='nearest', aspect='auto')
        axarr[0].set_title('Select = {%i, %.3f} and Skip = {%i, %.3f}' % (nsel, nsel/den, nskip, nskip/den))
        axarr[0].set_xlabel('Estimated Optimal Actions')
        axarr[0].set_xticks([])
        axarr[1].plot(cdfp['predOptimal'], cdfp['cumpercent'], label='Predicted', c='blue')
        axarr[1].plot(cdfa['actual'], cdfa['cumpercent'], label='Actual', c='red')
        axarr[1].set_ylim([0,1])
        axarr[1].set_xlim([llow, lhigh])
        axarr[1].set_xlabel('CDF of Actual and Predicted Rouge')
        axarr[1].legend(loc ='upper left')
        axarr[1].grid()
        axarr[1].set_title('%s %s model performance at epoch %i = %.3f' % (metric, model, epoch, rouge))
        f.tight_layout()
        f.savefig('./Code/plotdata/%s/plotfiles/perfplot_%i.png' % (model, epoch) )

    # Exporting the images to a gif
    file_names = [ ('./Code/plotdata/%s/plotfiles/perfplot_%i.png' % (model, epoch)) for epoch in range(nepochs)]
    images = []
    for filename in file_names:
        images.append(imageio.imread(filename))
        # Actual v Predicted gif
    imageio.mimsave('./Code/Performance/Simulation/%s_perf.gif' % model, images, duration=0.75)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])