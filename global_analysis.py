import pickle
import vc
import numpy as np
import matplotlib.pyplot as plt
import timeit
import networkx as nx

states = [2, 3, 4, 5, 6, 7, 8, 9, 10]
start = timeit.default_timer()

V_list = [0, 1, 3, 4, 6, 9, 10, 11]
temperatures = [0.01, 0.5, 1, 1.5, 2.0, 2.5, 5, 10, np.inf] # np.arange(0.01)
samples = np.arange(0, 10, 1)

def calculate_VNs(V_list, temperatures, samples):
    V_dict = pickle.load(open("experiments_with_V/V_matrices.p", "rb"))
    VN_count_dict = {}
    VN_count_std_dict = {}
    VN_count_sample = {}
    VN_count_sample_nodes = {}

    for v in V_list:
        V = V_dict[f'{v}']

        print(f'experiment{v}of29_{V.shape[0]}')

        state = V.shape[0]
        G_init, V, system_hamiltonian, A, fm = vc.simulate(1, state, V, 1)

        filename = f'experiments_with_V/experiment_3/vmatrixrun_{v}'
        infile = open(filename,'rb')
        runs = pickle.load(infile)
        infile.close()

        ts_arr = np.arange(0, 100000, 100)
        i = 0
        plt.figure()
        for temp in temperatures:
            timestep_avg = []
            timestep_std = []
            i += 1
            for timestep in ts_arr:
                avg = []
                for run in samples:
                    data = vc.VN_counter2(np.array(runs[f'run{state,temp,run}'].iloc[timestep, :100]), A, V)
                    avg.append(data[0])
                    VN_count_sample[f'{v, temp, timestep, run}'] = data[0]
                    VN_count_sample_nodes[f'{v, temp, timestep, run}'] = data[1]
                timestep_avg.append(avg)
                VN_count_dict[f'{v, temp, timestep}'] = avg
                # VN_count_std_dict[f'{v, temp, timestep}'] = timestep_std

    return VN_count_dict, VN_count_std_dict, VN_count_sample, VN_count_sample_nodes

VN_count_dict, VN_count_std_dict, VN_count_sample, VN_count_sample_nodes = calculate_VNs(V_list, temperatures, samples)

# for key in VN_count_dict.keys():
#     print(key)

filename = 'VN_count_dict'
outfile = open(filename,'wb')
pickle.dump(VN_count_dict, outfile)
outfile.close()

filename = 'VN_count_std_dict'
outfile = open(filename,'wb')
pickle.dump(VN_count_std_dict, outfile)
outfile.close()

filename = 'VN_count_sample'
outfile = open(filename,'wb')
pickle.dump(VN_count_sample, outfile)
outfile.close()

filename = 'VN_count_sample_nodes'
outfile = open(filename,'wb')
pickle.dump(VN_count_sample_nodes, outfile)
outfile.close()