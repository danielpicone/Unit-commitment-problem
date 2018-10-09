# Solving the unit commitment problem
using CPLEX
using JuMP
# First solve D_i

T = 17520
capacity = 10
# μ = 100*ones(T)
μ = 60*(rand(T)-0.5)
cost = 100
min_gen = 0.2
ramp_rate = 0.3

subprob = JuMP.Model(solver = CplexSolver(CPXPARAM_ScreenOutput = 1, CPXPARAM_Preprocessing_Dual=-1, CPXPARAM_MIP_Display = 4))

@variable(subprob, 1>=x[t=1:T]>=0)
@variable(subprob, y[t=1:T], Bin)

@objective(subprob, Min, sum(cost*x[t] - capacity*μ[t]*x[t] for t=1:T))

# Min gen constraints
@constraint(subprob, min_gen1[t=1:T], x[t] >= min_gen*y[t])
@constraint(subprob, min_gen2[t=1:T], x[t] <= y[t])
# Ramp rate constraints
@constraint(subprob, ramp_down[t=1:T-1], x[t] - x[t+1] <= ramp_rate)
@constraint(subprob, ramp_up[t=1:T-1], x[t] - x[t+1] >= -ramp_rate)
