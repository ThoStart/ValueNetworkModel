cimport cython

import numpy as np
cimport numpy as np
import networkx as nx
from scipy.linalg import toeplitz
import networkx as nx
import matplotlib.pyplot as plt
import pandas as pd
import pickle
import timeit
import heapq

cpdef tuple initialize_lattice(int L, int states):
    '''Inititalizes a lattice graph including states and an adjency matrix'''
    # init graph
    G = nx.grid_2d_graph(L,L, periodic=True)
    cdef int length = len(G.nodes())
    
    # assign random state to each node and put in array
    cdef np.ndarray G2 = np.random.randint(low=0, high=states, size=length)
    
    # adjency matrix
    cdef np.ndarray A = nx.adjacency_matrix(G).todense()
    
    return G2, A

cdef np.ndarray neighbors(A, node):
    '''Return an numpy array containing the neighbors of a node'''
    cdef np.ndarray nb = np.where(A[node]==1)[1]
    return nb

cdef np.ndarray init_V(int states, int option):
    '''
    Interaction matrix initialization
    Options:
    - 1: Standard Q-Potts model V matrix
    - 2: Non-directional Value Chain encoding
    - 3: Path 5 states
    '''
    assert states > 1, 'number of states needs to be more than 1'
    cdef np.ndarray V

    if option == 1:
        V = np.identity((states))
        if states == 2:
            V = np.array([[0, 1],\
                          [1, 0]])
        
    if option == 2:
        if states == 2: # A <-> A , B <-> B
            V = np.array([[0, 1],\
                          [1, 0]])
        else:
            first_row = np.zeros(states)
            first_row[1] = 1
            first_col = np.zeros(states)
            first_col[1] = 1

            V = toeplitz(first_col, first_row)

    if option == 3:
        V = np.array([[0, 1, 1, 1, 1],
                      [1, 0, 0, 0, 0],
                      [1, 0, 0, 0, 0],
                      [1, 0, 0, 0, 0],
                      [1, 0, 0, 0, 0]])
    return V

cdef float hamiltonian(G, int node, np.ndarray nb, np.ndarray V):
    '''
    Hamiltonian function: Calculate the energy for each bond of a single node
    , return the sum of these energies

    H: Hamiltonian
    cur_node: investigated current node
    cur_nb: investigated current neighbor
    kronecker (not used): 1 if two nodes are in same state
    '''
    cdef float H = 0
    cdef int cur_node = G[node]
    cdef int cur_nb
    cdef int kronecker
    
    # loop through all neighbors
    for i in range(len(nb)):
        cur_nb = G[nb[i]]
        kronecker = 0
        
        # check if states are the same
        H -= V[cur_node, cur_nb]
    return H
    
cdef metropolis(G, A, V, int states, float beta, int time, float system_hamiltonian):
    '''
    Performs all metropolis algorithm steps.
    
    Difference in energy is - (H2 (=new state) - H1 (=old state)) .
    System hamiltonian and magnetization is changed.
    '''
    cdef int rand_node
    cdef int spin
    cdef float dE = 0
    cdef int rand_state
    cdef float p
    cdef float H1 
    cdef float H2
    cdef list sh = []
    cdef list fm = []
    cdef np.ndarray arr

    fm.append(G.mean())
    cdef list history_arr = []
    
    for t in range(time):
        arr = np.arange(100)
        np.random.shuffle(arr)
        for i in range(len(G)):
            # pick random node
            # rand_node = np.random.randint(len(G)-1)

            # pick (binned) random node from 0 - 100
            rand_node = arr[i]
            spin = G[rand_node]
            
            rand_state = np.random.randint(states)
            while rand_state == spin:
                rand_state = np.random.randint(states)
            
            # calculate hamiltonian for current configuration
            nb = neighbors(A, rand_node)
            H1 = hamiltonian(G, rand_node, nb, V)
                        
            # calculate hamiltonian for new configuration
            G_copy = G.copy()
            G_copy[rand_node] = rand_state
            H2 = hamiltonian(G_copy, rand_node, nb, V)
            
            # calculate energy difference
            dE = (H2 - H1)
                        
            # energy may always be decreased
            if dE <= 0:
                p = 1   
                
            # probability proportional to Boltzmann distribution.
            else: 
                p = np.exp(-beta*dE)
                
            # energy is increased with probability
            if np.random.random() <= p:
                G[rand_node] = rand_state
                system_hamiltonian += dE
                
            # change configuration back to the original
            else: 
                G[rand_node] = spin
    
            sh.append(system_hamiltonian)
            fm.append(G.mean())
            history_arr.append(G.copy())

    return G, sh, history_arr

### Analysis functions
cdef float full_hamiltonian(G, A, V):
    '''
    Returns the energy state of the system.
    '''
    cdef float system_hamiltonian = 0 
    for i in range(len(G)):
        nb = neighbors(A, i)
        system_hamiltonian += hamiltonian(G, G[i], nb, V)
    return 0.5 * system_hamiltonian

### Satisfaction functions
cdef float full_satisfaction(G, A, V):
    'returns average satisfaction of the nodes'
    cdef float system_satisfaction = 0
    for i in range(len(G)):
        nb = neighbors(A, i)
        system_satisfaction += local_satisfaction(G, G[i], nb, V)
    return system_satisfaction * 0.5

cdef float local_satisfaction(G, int node, np.ndarray nb, np.ndarray V):
    cdef int cur_node = G[node]
    cdef int cur_nb
    cdef int s = 0
    
    # loop through all neighbors
    for i in range(len(nb)):
        cur_nb = G[nb[i]]
        if V[cur_node, cur_nb] == 0:
            s -=0
        else: 
            s += 1  
    return s

### Find value chain functions

cdef path_chains(G, A, V):
    '''
    This functions returns the number of full value chains present in the network.
    '''
    cdef np.ndarray nb
    # determine VC length
    cdef int VC_length = V.shape[0]
    cdef np.ndarray chains_of_length = np.zeros((VC_length))
    cdef np.ndarray nodes_in_state = np.zeros((VC_length))
    
    # find starting points of VC e.g. where state == 0
    cdef start_nodes = np.where(G==0)[0]
    cdef list nodes_in_chain = []
    
    nodes_in_chain.append(start_nodes)
    chains_of_length[0] = len(start_nodes)
  
    for state in range(VC_length):
        c = []
        for node in nodes_in_chain[state]:
#             print("node", node)
            nb = neighbors(A, node)
            for i in range(len(nb)):
            # TODO change to V matrix
                if G[nb[i]] == (state + 1):
#                   print(nb[i])
                    c.append(nb[i])
                    chains_of_length[state + 1] = len(c)
        nodes_in_chain.append(c)
    return chains_of_length

cdef plus_chains(G, A, V):
    cdef np.ndarray nb
    # determine VC length
    cdef int VC_length = V.shape[0]
    cdef np.ndarray nodes_in_state = np.zeros((VC_length))

    # find starting points of VC e.g. where state == 0
    cdef start_nodes = np.where(G==0)[0]
    cdef list nodes_in_chain = []
    nodes_in_chain.append(start_nodes)
    cdef int counter = 0
    cdef int node_counter = 0

    for node in nodes_in_chain[state]:
        node_counter = 0
        nb = neighbors(A, node)
        for state in range(VC_length):
            for i in range(len(nb)):
                if G[nb[i]] == state and G[nb[i]] != 0:
                    nodes_in_chain.append(nb[i])
                    node_counter+=1
                    break
        if node_counter == VC_length-1:
            counter += 1

    return counter

cdef local_chain_satisfactions(G, A, V):
    cdef np.ndarray nb
    cdef satisfaction = 0
    cdef G_satisfaction = []
    cdef int node_i = 0
    cdef int state_node = 0 

    for node_i, state_node in enumerate(G):
        satisfaction = 0
        nb = neighbors(A, node_i)
        for i in range(len(nb)):
            if V[int(state_node), int(G[nb[i]])] == 1:
                satisfaction += 1
            else:
                satisfaction -= 0
                
        G_satisfaction.append(satisfaction)
    return G_satisfaction

### Simulation functions
def init_V_py(states, option):
    V = init_V(states, option)
    return V

def check(G, A, V):
    c = path_chains(G, A, V)
    return c

def plus_check(G, A, V):
    c = plus_chains(G, A, V)
    return c

def check_local(G, A, V):
    G_satisfaction = local_chain_satisfactions(G, A, V)
    # print(np.array(G_satisfaction).reshape(10,10))
    return np.mean(G_satisfaction)

def check_local_vector(G, A, V):
    G_satisfaction = local_chain_satisfactions(G, A, V)
    return G_satisfaction

def sep_ham(fm, A, V):
   hamiltonian_string = []
   for step in range(len(fm)+1):
        hamiltonian_string.append(full_hamiltonian(fm[step], A, V))
   return hamiltonian_string
    
def sep_sat(fm, A, V):
    l= []
    for step in range(len(fm)):
        l.append(full_satisfaction(fm[step], A, V))
    return l

def put_in_dataframe(fm, system_hamiltonian, A, V):
    '''
    Save data in convenient manner using pandas dataframe for each run, which is stored in a dictionary.
    '''
    df = pd.DataFrame(data=fm)
    # put energy value of timestep in last column
#     df.loc[:, fm[0].shape[0]+1] = check(fm, A, V) # complete Value Chains
    df.loc[:, fm[0].shape[0]+2] = system_hamiltonian # phase of system
    df.loc[:, fm[0].shape[0]+3] = check_local(fm[-1], A, V) # local satisfaction
    return df

def printProgressBar (iteration, total, prefix = '', suffix = '', decimals = 1, length = 100, fill = '???', printEnd = "\r"):
    """
    Call in a loop to create terminal progress bar
    @params:
        iteration   - Required  : current iteration (Int)
        total       - Required  : total iterations (Int)
        prefix      - Optional  : prefix string (Str)
        suffix      - Optional  : suffix string (Str)
        decimals    - Optional  : positive number of decimals in percent complete (Int)
        length      - Optional  : character length of bar (Int)
        fill        - Optional  : bar fill character (Str)
        printEnd    - Optional  : end character (e.g. "\r", "\r\n") (Str)
    """
    percent = ("{0:." + str(decimals) + "f}").format(100 * (iteration / float(total)))
    filledLength = int(length * iteration // total)
    bar = fill * filledLength + '-' * (length - filledLength)
    print(f'\r{prefix} {bar} {percent}% {suffix}, {printEnd}')
    # Print New Line on Complete
    if iteration == total: 
        print()

def simulate(T, states, V, timesteps):
    lattice_size = 10
    G, A = initialize_lattice(lattice_size, states)
    G_init = G.copy()
    sh = full_hamiltonian(G,A,V)
    beta = 1 / T
    M, system_hamiltonian, fm = metropolis(G, A, V, states, beta, timesteps, sh)
    return G_init, V, system_hamiltonian, A, fm

def perform_tests(temperatures, states, samples, V, timesteps):
    '''
    Perform multiple simulations with different input parameters.
    Saves the system-hamiltonian per step of multiple runs.
    '''
    l = len(temperatures) * len(states) * len(samples)
    i = 0
    # printProgressBar(0, l, prefix = 'Progress:', suffix = 'Complete', length = 100)

    runs = {}
    for state in states:
        for temp in temperatures:
            print(temp)
            for run in samples:
                print(run)
                G_init, V, system_hamiltonian, A, fm = simulate(temp, state, V, timesteps)
                df = put_in_dataframe(fm, system_hamiltonian, A, V)
                runs[f'run{state,temp,run}'] = df

                # printProgressBar(i + 1, l, prefix = 'Progress:', suffix = 'Complete', length = 100)
                i += 1
    return runs

def VN_counter(G, A, V):
    g = nx.from_numpy_matrix(V, create_using=nx.DiGraph)
    g.edges()
    #  nx.draw(g, with_labels=1)
    V_mapping = nx.convert.to_dict_of_lists(g)

    sorted_items = heapq.nlargest(len(V_mapping), V_mapping.items(), key=lambda x: len(x[1]))
    V_mapping = dict(sorted_items)

    # print(G.reshape(10,10))

    # first make a dictionary with nodes that are satisfying the requirements
    sat_dict = {}
    for key in V_mapping:
        start_nodes = np.where(G==key)[0]
        sat_list = []
        for node in start_nodes:
            nb = neighbors(A, node)
            node_struct = []
            for i in range(len(nb)):
                node_struct.append(G[nb[i]])
            if all(elem in node_struct for elem in V_mapping[key]):
                sat_list.append(node)

        sat_dict[key] = sat_list

    # print(sat_dict)
    # print(V_mapping)


    # second check if the full Value Network is satisfied
    nodes_checked = []
    VN_counter = 0
    meets_req = []
    meets_req2 = []

    for key in sat_dict:
        requirements = np.zeros((V.shape[0]))

        # add node to VN
        for node in sat_dict[key]:
#             print(node)
            requirements = np.zeros((V.shape[0]))
            meets_req2.append(node)
#             meets_req.append(node)
            requirements[int(G[node])] = 1

            if node in nodes_checked:
                continue

            # see if nb are in VN
            nb = neighbors(A, node)
            for i in range(len(nb)):
                if nb[i] in sat_dict[int(G[nb[i]])] and nb[i] not in nodes_checked:
                    requirements[int(G[nb[i]])] = 1
                    meets_req.append(nb[i])

#             print(meets_req)

            if requirements.all() == 1:
                VN_counter += 1
                requirements = np.zeros((V.shape[0]))

                without_doubles = []
                for nd in meets_req:
                    if requirements[int(G[nd])] == 0:
                        without_doubles.append(nd)
                        requirements[int(G[nd])] = 1

                nodes_checked.extend(without_doubles)
#                 print(meets_req)
#                 print(without_doubles)
#                 print("yeah 1st time")
                meets_req = []



            else:
                for x in range(0, len(meets_req)-1):

                    nb2 = neighbors(A, meets_req[x])

                    for j in range(len(nb2)):
                        if nb2[j] != node and nb2[j] in sat_dict[int(G[nb2[j]])] and G[int(nb2[j])] in V_mapping[int(G[meets_req[x]])] and nb2[j] not in nodes_checked:
                            if requirements[int(G[nb2[j]])] != 1:
                                meets_req2.append(meets_req[x])
                                meets_req2.append(nb2[j])
                                requirements[int(G[nb2[j]])] = 1

                        if requirements.all() == 1:
#                             print(meets_req, meets_req2)
                            VN_counter += 1
                            requirements_test = np.zeros((V.shape[0]))
                            nodes_checked.extend(meets_req2)
#                             print(requirements)
                            requirements = np.zeros((V.shape[0]))
                            break
            meets_req = []
            meets_req2 = []
#     print("VN", VN_counter)
#     print(len(nodes_checked), nodes_checked)
    return VN_counter

# This VN counter is used for the experiments
def VN_counter2(G, A, V):
    g = nx.from_numpy_matrix(V, create_using=nx.DiGraph)
    g.edges()
#     nx.draw(g, with_labels=1)
    V_mapping = nx.convert.to_dict_of_lists(g)

    sorted_items = heapq.nlargest(len(V_mapping), V_mapping.items(), key=lambda x: len(x[1]))
    V_mapping = dict(sorted_items)

#     print(G.reshape(10,10))

    # first make a dictionary with nodes that are satisfying the requirements
    sat_dict = {}
    for key in V_mapping:
        start_nodes = np.where(G==key)[0]
        sat_list = []
        for node in start_nodes:
            nb = neighbors(A, node)
            node_struct = []
            for i in range(len(nb)):
                node_struct.append(G[nb[i]])
            if all(elem in node_struct for elem in V_mapping[key]):
                sat_list.append(node)

        sat_dict[key] = sat_list

   # print(sat_dict)
#     print(V_mapping)


    # second check if the full Value Network is satisfied
    nodes_checked = []
    VN_counter = 0
    meets_req = []
    meets_req2 = []

    for key in sat_dict:
        requirements = np.zeros((V.shape[0]))

        # add node to VN
        for node in sat_dict[key]:
#             print(node)
            requirements = np.zeros((V.shape[0]))
            meets_req2.append(node)
            meets_req.append(node)
            requirements[int(G[node])] = 1

            if node in nodes_checked:
                continue

            # see if nb are in VN
            nb = neighbors(A, node)
            for i in range(len(nb)):
                if nb[i] in sat_dict[int(G[nb[i]])] and nb[i] not in nodes_checked and G[int(nb[i])] in V_mapping[int(G[node])]:
                    requirements[int(G[nb[i]])] = 1
                    meets_req.append(nb[i])

#             print(meets_req)

            if requirements.all() == 1:
                # print("meets_req", meets_req)
                VN_counter += 1
                requirements = np.zeros((V.shape[0]))

                without_doubles = []
                for nd in meets_req:
                    if requirements[int(G[nd])] == 0:
                        without_doubles.append(nd)
                        requirements[int(G[nd])] = 1

                nodes_checked.extend(without_doubles)
                # print("meets_req", without_doubles)


#                 print(meets_req)
#                 print(without_doubles)
#                 print("yeah 1st time")
                meets_req = []



            else:
                for x in range(0, len(meets_req)-1):

                    nb2 = neighbors(A, meets_req[x])

                    for j in range(len(nb2)):
#                         print(nb2[j])
                        if nb2[j] != node and nb2[j] in sat_dict[int(G[nb2[j]])] and G[int(nb2[j])] in V_mapping[int(G[meets_req[x]])] and nb2[j] not in nodes_checked:
                            if requirements[int(G[nb2[j]])] != 1:
#                                 print(nb2[j])
                                meets_req2.append(meets_req[x])
                                meets_req2.append(nb2[j])
                                requirements[int(G[nb2[j]])] = 1

                        if requirements.all() == 1:
                            # print("yolo", node, meets_req, meets_req2)
                            VN_counter += 1
                            requirements_test = np.zeros((V.shape[0]))
                            nodes_checked.extend(meets_req2)
#                             print(requirements)
                            requirements = np.zeros((V.shape[0]))
                            break
            meets_req = []
            meets_req2 = []
#     print("VN", VN_counter)
#     print(len(nodes_checked), nodes_checked)
    return VN_counter, nodes_checked



