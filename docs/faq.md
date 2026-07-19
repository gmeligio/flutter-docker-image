# FAQ

## Why the images are not published in the AWS ECR Public registry?

The storage of the images starts to cost after 50 GB and increases with every pushed image because the AWS Free Tier covers up to 50 GB of total storage for free in ECR Public.

## Why there is no dynamic tag like `latest`?

There is no `latest` Docker tag on purpose. You need to specify the version of the image you want to use. The reason for that is that `latest` can cause unexpected behavior when rerunning a past CI job that was expected to use the old build of the `latest` tag. There are multiple articles explaining more about this reasoning like [What's Wrong With The Docker :latest Tag?](https://vsupalov.com/docker-latest-tag/) and [The misunderstood Docker tag: latest](https://medium.com/@mccode/the-misunderstood-docker-tag-latest-af3babfd6375).
