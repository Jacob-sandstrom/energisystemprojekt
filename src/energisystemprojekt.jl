# I den här filen bygger ni modellen. Notera att det är skrivet som en modul, dvs ett paket. 
# Så när ni ska använda det, så skriver ni Using energisystemprojekt i er REPL, då får ni ut det ni
# exporterat. Se rad 9.

module energisystemprojekt


using JuMP, AxisArrays, Gurobi, UnPack

export runmodel

include("input_energisystemprojekt.jl")

function buildmodel(input)

    println("\nBuilding model...")
 
    @unpack REGION, PLANT, HOUR, numregions, load, maxcap, ic, rc, fc, lt, ac, wind_cf, pv_cf, inflow = input

    m = Model(Gurobi.Optimizer)

    @variables m begin

        Electricity[r in REGION, p in PLANT, h in HOUR]         >= 0        # MWh/h
        Capacity[r in REGION, p in PLANT]                       >= 0        # MW

        Systemcost[r in REGION]                                 >= 0
        ReservoirLevel[h in HOUR]                               >= 0         #MW
        
        Co2[r in REGION]                                        >= 0
        
        # Excercise 2
        # b
        BatteryCharge[r in REGION, h in HOUR]                   >= 0

        # Excercise 3
        Transmission[r1 in REGION, r2 in REGION, h in HOUR]     >= 0          # first region is sender second is reciever
        TransmissionCap[r1 in REGION, r2 in REGION]             >= 0          # first region is sender second is reciever

    end #variables


    #Variable bounds
    for r in REGION, p in PLANT
        set_upper_bound(Capacity[r, p], maxcap[r, p])
    end


    @constraints m begin
        GenerationGH[r in REGION, p in [:Gas, :Hydro], h in HOUR],
            Electricity[r, p, h] <= Capacity[r, p] # * capacity factor

        GenerationW[r in REGION, h in HOUR],
            Electricity[r, :Wind, h] <= Capacity[r, :Wind] * wind_cf[r, h]

        GenerationP[r in REGION, h in HOUR],
            Electricity[r, :PV, h] <= Capacity[r, :PV] * pv_cf[r, h]

        Load[r in REGION, h in HOUR],
            sum(Electricity[r, p, h] for p in PLANT) >= load[r,h]


        rescap[h in HOUR],
            ReservoirLevel[h] <= 33000000

        ReservoirLevel[1] == ReservoirLevel[length(HOUR)]

        resChange[h in 1:length(HOUR)-1],
            ReservoirLevel[h+1] == ReservoirLevel[h] + inflow[h]- Electricity[:SE, :Hydro, h]
        

        CO2[r in REGION],
            Co2[r] == sum(Electricity[r, :Gas, h]/0.4*0.202 for h in HOUR)

        
        SystemCost[r in REGION],
            Systemcost[r] >= sum(ac[p]*Capacity[r, p] for p in PLANT) +
                sum(rc[p]*Electricity[r, p, h] for p in PLANT, h in HOUR) # sum of all annualized costs
    

        # Excercise 2
        # a

        # Model cant be solved with this req
        # sum(Co2[r] for r in REGION) <= 0.1* 1.387744849926479e8

        # b
        BatteryCap[r in REGION, h in HOUR],
            BatteryCharge[r, h] <= Capacity[r, :Battery]

        GenerationB[r in REGION, h in HOUR],
            Electricity[r, :Battery, h] <= BatteryCharge[r, h]

        Charge[r in REGION, h in 1:length(HOUR)-1],
            BatteryCharge[r, h+1] == BatteryCharge[r, h] - Electricity[r, :Battery, h] + 
                0.9 * (sum(Electricity[r, p, h] for p in PLANT[PLANT .!= :Battery]) - load[r,h])  



        # Excercise 3
        MirrorTransmissionCap[r1 in REGION, r2 in REGION],
            TransmissionCap[r1, r2] == TransmissionCap[r2, r1]

        TransCap[r1 in REGION, r2 in REGION, h in HOUR],
            Transmission[r1, r2, h] <= TransmissionCap[r1, r2]

        Transmit[r1 in REGION, h in HOUR],
            sum(Transmission[r1, r2, h] for r2 in REGION) == 
                0.98 * (sum(Electricity[r1, p, h] for p in PLANT) - load[r1,h])  

        GenerationT[r2 in REGION, h in HOUR],
            Electricity[r2, :Transmission, h] == sum(Transmission[r1, r2, h] for r1 in REGION)

            
        # NoSelfTransmission[r in REGION],
        #     TransmissionCap[r, r] == 0


    end #constraints

    # print("\n\n\n\n")
    # println(Electricity[:SE, :Transmission, 1])
    # print("\n\n\n\n")

    @objective m Min begin
        sum(Systemcost[r] for r in REGION)
    end # objective

    return (;m, Capacity, Co2, ReservoirLevel, TransmissionCap)

end # buildmodel

function runmodel() 

    input = read_input()

    model = buildmodel(input)

    @unpack m, Capacity, Co2, ReservoirLevel, TransmissionCap = model   
    
    println("\nSolving model...")
    
    status = optimize!(m)
    

    if termination_status(m) == MOI.OPTIMAL
        println("\nSolve status: Optimal")   
    elseif termination_status(m) == MOI.TIME_LIMIT && has_values(m)
        println("\nSolve status: Reached the time-limit")
    else
        error("The model was not solved correctly.")
    end

    Cost_result = objective_value(m)/1000000 # M€
    Capacity_result = value.(Capacity)

    println("\ncapacity: ", Capacity_result)
    println("\nReservoir level: ",value.(ReservoirLevel)[8760])
    println("\nCo2: ", sum(value.(Co2)))
    println("\nTransmissionCap: ", value.(TransmissionCap))
    println("\nCost (M€): ", Cost_result)
   

    nothing

end #runmodel



end # module

