# Solving the unit commitment problem
using CPLEX
using JuMP
using YAML
# First solve D_i
srand(100)

T = 5
# demand = 40*rand(T)
demand = 40*ones(T)
u = opt_dual
generators = YAML.open(load("generators.yml"))
subprob = Dict()

# subprob = JuMP.Model(solver = CplexSolver(CPXPARAM_ScreenOutput = 1, CPXPARAM_Preprocessing_Dual=-1, CPXPARAM_MIP_Display = 4))
for gen=1:n
    subprob[gen] = JuMP.Model(solver = CplexSolver(CPXPARAM_ScreenOutput = 0, CPXPARAM_Preprocessing_Dual=-1, CPXPARAM_MIP_Display = 0))
end

for gen=1:n
    @variable(subprob[gen], 1>=x[gen, t=1:T]>=0)
    # @variable(subprob[gen], y[gen, t=1:T], Bin)
    @variable(subprob[gen], 1>=y[gen, t=1:T]>=0)

    @objective(subprob[gen], Min, sum(cost[gen] * capacity[gen] * x[gen, t] - capacity[gen]*u[t]*x[gen, t] for t=1:T))

    # Min gen constraints
    @constraint(subprob[gen], min_gen1[gen, t=1:T], x[gen, t] >= min_gen[gen]*y[gen, t])
    @constraint(subprob[gen], min_gen2[gen, t=1:T], x[gen, t] <= y[gen, t])
    # Ramp rate constraints
    @constraint(subprob[gen], ramp_down[gen, t=1:T-1], x[gen, t] - x[gen, t+1] <= ramp_rate[gen])
    @constraint(subprob[gen], ramp_up[gen, t=1:T-1], x[gen, t] - x[gen, t+1] >= -ramp_rate[gen])
end

function get_subgradient(subproblems)
    subgradient = zeros(T)
    for t=1:T
        subgradient[t] = demand[t] - sum(capacity[gen] * getvalue(Variable.(subprob[gen],t)) for gen=1:n)
    end
    return subgradient
end

function solve_subproblems!(subproblems)
    for gen=1:n
        solve(subprob[gen])
    end
end

function update_objectives!(subproblems, u)
    for gen=1:n
        vars = Variable.(subprob[gen],1:T)
        @objective(subprob[gen], Min, sum(cost[gen] * capacity[gen] * vars[t] - capacity[gen]*u[t]*vars[t] for t=1:T))
    end
end


function get_objective_value(cost, subgradient, lagrange_multipliers)
    return sum((capacity.*cost*ones(T)')[gen,t] * getvalue(Variable.(subprob[gen],t)) for gen=1:n,t=1:T) + lagrange_multipliers' * subgradient
end

function get_objective_value(cost)
    return sum((capacity.*cost*ones(T)')[gen,t] * getvalue(Variable.(subprob[gen],t)) for gen=1:n,t=1:T)
end

function generation_output(vars_x, capacity)
    return vars' * capacity
end

k = 0
# u = opt_dual
u = zeros(T)
μ = 10


for k=1:5000
    update_objectives!(subprob, u)
    solve_subproblems!(subprob)
    sub_grad = get_subgradient(subprob)
    obj_val = get_objective_value(cost)
    if k % 200 == 0
        μ = 100/(1+k)
        # μ = 0.5*μ
        println("Objective value is: ", obj_val)
        println("The norm of the subgradient is: ", norm(sub_grad))
        println("Step size: ", μ)
    end
    u = u + μ * sub_grad
end

vars_x = zeros(n,T)
for gen=1:n
    vars_x[gen,:] = getvalue(Variable.(subprob[gen],1:T))
end

vars_y = zeros(n,T)
for gen=1:n
    vars_y[gen,:] = getvalue(Variable.(subprob[gen],T+1:2*T))
end
