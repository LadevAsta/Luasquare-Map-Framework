DFR = DFR or {}
DFR.Config = DFR.Config or {}

local config = DFR.Config

config.TickInterval = config.TickInterval or 0.1
config.MaxDeltaTime = config.MaxDeltaTime or 0.5
config.DefaultControlLockSeconds = config.DefaultControlLockSeconds or 0.35
config.StartupLeverArmWindow = config.StartupLeverArmWindow or 5.0
config.StartupRequiredFuelReceptacles = config.StartupRequiredFuelReceptacles or 3

config.InitialMatterReservePercent = config.InitialMatterReservePercent or 100
config.InitialAntimatterReservePercent = config.InitialAntimatterReservePercent or 100
config.InitialFuelReceptacleCount = config.InitialFuelReceptacleCount or 3
config.InitialDecaosOnline = config.InitialDecaosOnline ~= false
config.InitialSuperstructureIntegrityPercent = config.InitialSuperstructureIntegrityPercent or 100
config.OfflineIntegrityRecoveryPerSecond = config.OfflineIntegrityRecoveryPerSecond or 0.02

config.StabilizerStartupPowerGW = config.StabilizerStartupPowerGW or 8
config.StabilizerRampUpSeconds = config.StabilizerRampUpSeconds or 5
config.StabilizerRampDownSeconds = config.StabilizerRampDownSeconds or 3
config.CoreFormationThresholdFraction = config.CoreFormationThresholdFraction or 0.15
config.StartupCoreSphereRadiusMeters = config.StartupCoreSphereRadiusMeters or 2.6
config.StartupCoreShieldRadiusMeters = config.StartupCoreShieldRadiusMeters or 3.0
config.CoreShieldMinimumMarginMeters = config.CoreShieldMinimumMarginMeters or 0.5
config.MinimumAvailableCatalyzers = config.MinimumAvailableCatalyzers or 1
config.ContainmentFieldStepPercent = config.ContainmentFieldStepPercent or 5
config.ContainmentFieldStartupLimitPercent = config.ContainmentFieldStartupLimitPercent or 35
config.LensOffsetStep = config.LensOffsetStep or 0.025
config.DirectorBeamAutoDriftPerSecond = config.DirectorBeamAutoDriftPerSecond or 0.0008

config.TimerName = config.TimerName or 'LUASQUARE_DFR_UpdateTimer'
