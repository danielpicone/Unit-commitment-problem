# Solving the unit commitment problem
using CPLEX
using JuMP
using YAML
using DataFrames
using Gadfly
# First solve D_i
srand(100)

T = 48
demand = 40+10*rand(T)
# demand = 40*ones(T)
u = opt_dual
generators = YAML.load(open("generators.yml"))
subprob = Dict()

# subprob = JuMP.Model(solver = CplexSolver(CPXPARAM_ScreenOutput = 1, CPXPARAM_Preprocessing_Dual=-1, CPXPARAM_MIP_Display = 4))
for gen in keys(generators)
    subprob[gen] = JuMP.Model(solver = CplexSolver(CPXPARAM_ScreenOutput = 0, CPXPARAM_Preprocessing_Dual=-1, CPXPARAM_MIP_Display = 0))
end

for (gen, d) in generators
    @variable(subprob[gen], 1>=x[keys(generators), t=1:T]>=0)
    @variable(subprob[gen], y[keys(generators), t=1:T], Bin)
    # @variable(subprob[gen], startup[keys(generators), t=1:T], Bin)

    @objective(subprob[gen], Min, sum(d["cost"] * d["capacity"] * x[gen, t] -
        d["capacity"]*u[t]*x[gen, t]
        for t=1:T))
        # d["startup"] * startup[gen,t] for t=1:T))

    # Min gen constraints
    @constraint(subprob[gen], min_gen1[gen, t=1:T], d["mingen"]*x[gen, t] >= d["mingen"]*y[gen, t])
    @constraint(subprob[gen], min_gen2[gen, t=1:T], x[gen, t] <= y[gen, t])
    # Ramp rate constraints
    @constraint(subprob[gen], ramp_down[gen, t=1:T-1], x[gen, t] - x[gen, t+1] <= d["ramp"])
    @constraint(subprob[gen], ramp_up[gen, t=1:T-1], x[gen, t] - x[gen, t+1] >= -d["ramp"])
    # Start up constraint
    # @constraint(subprob[gen], start_up[gen in keys(generators), t=2:T], startup[gen,t]>=y[gen,t]-y[gen,t-1])
end
#
function get_subgradient(subproblems)
    subgradient = zeros(T)
    for t=1:T
        subgradient[t] = demand[t] - sum(d["capacity"] * getvalue(Variable.(subprob[gen],t)) for (gen,d) in generators)
    end
    return subgradient
end

function solve_subproblems!(subproblems)
    for (gen,problem) in subproblems
        solve(problem)
    end
end

function update_objectives!(subproblems, u)
    for (gen,d) in generators
        x_vars = Variable.(subprob[gen],1:T)
        # startup_vars = Variable.(subprob[gen],:T)
        @objective(subprob[gen], Min, sum(d["cost"] * d["capacity"] * x_vars[t] - d["capacity"]*u[t]*x_vars[t] for t=1:T))
        # @objective(subprob[gen], Min, sum(d["cost"] * d["capacity"] * x_vars[t] -
        #     d["capacity"]*u[t]*x_vars[t] +
        #     d["startup"] * startup[gen,t] for t=1:T))
    end
end


function get_objective_value(cost, subgradient, lagrange_multipliers)
    return sum((capacity.*cost*ones(T)')[gen,t] * getvalue(Variable.(subprob[gen],t)) for gen in keys(generators),t=1:T) + lagrange_multipliers' * subgradient
end

function get_objective_value(cost)
    return sum((capacity.*cost*ones(T)')[gen,t] * getvalue(Variable.(subprob[gen],t)) for gen in keys(generators),t=1:T)
end

function generation_output(vars_x, capacity)
    return vars' * capacity
end

k = 0
# u = opt_dual
u = zeros(T)
μ = 10
sub_grad_array = []
dual_array = []


for k=1:1000
    update_objectives!(subprob, u)
    solve_subproblems!(subprob)
    sub_grad = get_subgradient(subprob)
    push!(sub_grad_array, sub_grad)
    # obj_val = get_objective_value(cost)
    μ = 100/(1+k)
    if k % 100 == 0
        # μ = 0.5*μ
        # println("Objective value is: ", obj_val)
        println("The norm of the subgradient is: ", norm(sub_grad))
        println("Step size: ", μ)
    end
    u = u + μ * sub_grad
    if k>900
        u = mean(dual_array[end-9:end])
    end
    push!(dual_array, u)
end

solve_subproblems!(subprob)
function create_variables_dict(generators)
    generation_vars = Dict()
    for gen in keys(generators)
        generation_vars[gen] = Dict("generation" => getvalue(Variable.(subprob[gen],1:T)),
        "on" => getvalue(Variable.(subprob[gen],T+1:2*T))
        )
    end
    return generation_vars
end

generation_vars = create_variables_dict(generators)

# Create the dataframe
function create_generation_df(generators)
    df = DataFrames.DataFrame(generator = String[], cost = Float64[], max_capacity = Float64[], interval = Float64[], generation = Float64[], demand = Float64[])
    for (gen, d) in generators
        for t=1:T
            push!(df, [gen d["cost"] d["capacity"] t d["capacity"]*generation_vars[gen]["generation"][t] demand[t]])
        end
    end
    return df
end

df = create_generation_df(generators)

demand_df = DataFrames.DataFrame(interval = collect(1:T+1)-0.5, demand = [demand;demand[end]])
plot(df,
   layer(demand_df, x=:interval,y=:demand,Geom.step, Theme(default_color="black")),
   layer(sort!(df, rev=true), x=:interval,y=:generation,color=:generator,Geom.bar))
