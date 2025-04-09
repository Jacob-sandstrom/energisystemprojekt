# I den här filen kan ni stoppa all inputdata. 
# Läs in datan ni fått som ligger på Canvas genom att använda paketen CSV och DataFrames

using CSV, DataFrames

function read_input()
    println("\nReading Input Data...")
    folder = dirname(@__FILE__)

    #Sets
    REGION = [:DE, :SE, :DK]
    PLANT = [:Wind,  :PV, :Gas, :Hydro] # Add all plants
    HOUR = 1:8760

    #Parameters
    numregions = length(REGION)
    numhours = length(HOUR)

    timeseries = CSV.read("$folder\\TimeSeries.csv", DataFrame)
    wind_cf = AxisArray(ones(numregions, numhours), REGION, HOUR)
    pv_cf = AxisArray(ones(numregions, numhours), REGION, HOUR)
    load = AxisArray(zeros(numregions, numhours), REGION, HOUR)

    inflow=timeseries[:, "Hydro_inflow"]                                                       
    
    for r in REGION
        wind_cf[r, :]=timeseries[:, "Wind_"*"$r"]                                                        # 0-1, share of installed cap
        pv_cf[r, :]=timeseries[:, "PV_"*"$r"]                                                           
        load[r, :]=timeseries[:, "Load_"*"$r"]    
    end

    myinf = 1e8
    maxcaptable = [                                                             # GW
        # PLANT      DE             SE              DK       
        :Wind        180            280             90       
        :PV          460            75              60      
        :Gas         myinf          myinf           myinf         
        :Hydro       0              14              0       
    ]

    maxcap = AxisArray(maxcaptable[:,2:end]'.*1000, REGION, PLANT) # MW


    discountrate=0.05

    ic = Dict(
        # PLANT     #Cost euro/MW
        :Wind   =>  1100000,
        :PV     =>  600000,
        :Gas    =>  550000,
        :Hydro  =>  0
    )

    rc = Dict(
        # PLANT     #Cost euro/MWh_elec
        :Wind   =>  0.1,
        :PV     =>  0.1,
        :Gas    =>  2 + 22/0.4,
        :Hydro  =>  0.1
    )

    fc = [
        # PLANT     #Cost euro/MWh_fuel
        :Wind       0
        :PV         0
        :Gas        22
        :Hydro      0
    ]

    lt = Dict(
        # PLANT     #lifetime years
        :Wind   =>  25,
        :PV     =>  25,
        :Gas    =>  30,
        :Hydro  =>  80
    )

        

    ac = Dict(
        # PLANT     #lifetime years
        :Wind   =>  ic[:Wind]*discountrate/(1-1/(1+discountrate)^lt[:Wind]),
        :PV     =>  ic[:PV]*discountrate/(1-1/(1+discountrate)^lt[:PV]),
        :Gas    =>  ic[:Gas]*discountrate/(1-1/(1+discountrate)^lt[:Gas]),
        :Hydro  =>  ic[:Hydro]*discountrate/(1-1/(1+discountrate)^lt[:Hydro])
    )



    return (; REGION, PLANT, HOUR, numregions, load, maxcap, ic, rc, fc, lt, ac, wind_cf, pv_cf, inflow)

end # read_input
