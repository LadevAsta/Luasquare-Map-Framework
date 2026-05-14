-- fluidnetwork.lua contains logic and api for managing many types of fluid networks.
-- Api will allow other modules to call upon this to change the value of the network.

-- In a Steamline network :
-- Pressure
-- Pumps and pipe for both steam and feedwater
-- Steam Drum to increase steam capacity can get overpressured.
-- Water tanks increase water capacity wont get overpressured but cause pump cavitation if pressure is too low.

-- Steamline can rupture from being overpressured which will greatly hurt flow rate and leaks by progressively reducing value.
-- When this occurs in a network, pick a random defined logic_relay to fire. (which should provide a way to 'fix' the leak)
-- If there are no logic_relay defined at all. Assume this as Godmode network and rupture will never happen.

-- Simple fluid network : basically fluid network but without pressure mechanic. Likely will be used for OCC(offline core cooling) to deal with decay heat once implemented.

-- Fluid network can have 'service pumps' which can be used to add more fluid into network if enabled in-map.