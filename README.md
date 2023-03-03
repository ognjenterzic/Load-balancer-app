# Load-balancer-app
This is my project where I have created alb using terraform.

So the main Idea was to deploy two ec2 instances with already deployed html templates(different). Structure was like this I have deployed two target groups
where I put machine01 in one target group and machine02 in another target group, so incoming traffic was routed based on the path in the url. For that I have deployed 
also listener rules.
