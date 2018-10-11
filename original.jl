
# Solving the unit commitment problem
using CPLEX
using JuMP
# First solve D_i
srand(100)

T = 5
n = 4
# demand = 40*rand(T)
demand = 40*ones(T)
capacity = [10,20,30,1000]
# μ = 100*ones(T)
μ = 60*(rand(T)-0.5)
cost = [100, 80, 110, 14000]
min_gen = [0.2, 0.4, 0.1, 0]
ramp_rate = [0.3, 0.5, 0.2, 1.0]

original = JuMP.Model(solver = CplexSolver(CPXPARAM_ScreenOutput = 1, CPXPARAM_Preprocessing_Dual=-1, CPXPARAM_MIP_Display = 4))

@variable(original, 1>=x[gen=1:n, t=1:T]>=0)
# @variable(original, y[gen=1:n, t=1:T], Bin)
@variable(original, 1>=y[gen=1:n, t=1:T]>=0)

@objective(original, Min, sum(cost[gen] * capacity[gen] * x[gen, t] for gen=1:n,t=1:T))

# Demand constraints
@constraint(original, demand_constraint[t=1:T], sum(capacity[gen]*x[gen,t] for gen=1:n) == demand[t])

# Min  constraints
@constraint(original, min_gen1[gen=1:n, t=1:T], x[gen, t] >= min_gen[gen]*y[gen, t])
@constraint(original, min_gen2[gen=1:n, t=1:T], x[gen, t] <= y[gen, t])
# Ramp rate constraints
@constraint(original, ramp_down[gen=1:n, t=1:T-1], x[gen, t] - x[gen, t+1] <= ramp_rate[gen])
@constraint(original, ramp_up[gen=1:n, t=1:T-1], x[gen, t] - x[gen, t+1] >= -ramp_rate[gen])

solve(original)
