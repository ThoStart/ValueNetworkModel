import pickle
import vc
import numpy as np
import timeit
import networkx as nx
import matplotlib.pyplot as plt

temperatures = [0.01, 0.5, 1, 1.5, 2.0, 2.5, 5, 10, np.inf] # np.arange(0.01)
samples = np.arange(0, 10, 1)
timesteps = 1000

V_dict = pickle.load(open("experiments_with_V/V_matrices.p", "rb"))

V_list = [0, 1, 3, 4, 6, 9, 10, 11]

start = timeit.default_timer()
for v in V_list:
    V = V_dict[f'{v}']
    print(f'experiment{v}of29_{V.shape[0]}')

    # filename = f'experiments_with_V/experiment_1/jmatrixrun_{v}'
    # infile = open(filename,'rb')
    # runs = pickle.load(infile)
    # infile.close()

    # plot the value graph
    # g = nx.from_numpy_matrix(J, create_using=nx.DiGraph)
    # g.edges()
    # nx.draw(g, with_labels=1)
    # plt.savefig(f'VC_config_experiment{j}of29')

    states_exp = [V.shape[0]]
    vmatrixrun = vc.perform_tests(temperatures, states_exp, samples, V, timesteps)

    runs = vmatrixrun

    filename = f'experiments_with_V/experiment_3/vmatrixrun_{v}'
    outfile = open(filename,'wb')
    pickle.dump(runs, outfile)
    outfile.close()

stop = timeit.default_timer()
print('Time: ', stop - start)

