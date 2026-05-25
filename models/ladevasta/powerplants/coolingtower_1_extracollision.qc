$modelname "ladevasta/powerplants/coolingtower_1_extracollision.mdl"

$body body "coolingtower_1_phys_extra1.smd"

$collisionmodel "coolingtower_1_phys_extra1.smd"
{
    $mass 10000
	$concave
	$maxconvexpieces 1000000
}

$staticprop
$surfaceprop "metal"

$sequence "idle" "coolingtower_1_phys_extra1.smd" fps 1