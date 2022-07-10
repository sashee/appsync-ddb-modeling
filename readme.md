## Deploy

* ```terraform init```
* ```terraform apply```

## Use

* Go to the AppSync console and send requests

### Run the pagination queries

* ```(cd queries && npm ci)```
* ```TABLE=$(terraform output --raw users_table) node queries/limits.mjs```

## Cleanup

* ```terraform destroy```
