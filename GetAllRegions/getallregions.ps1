$locations = get-azlocation | format-table 
$test = ConvertTo-Csv -InputObject $locations
$test


get-azlocation
