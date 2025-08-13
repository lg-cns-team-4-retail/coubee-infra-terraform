def lambda_handler(event, context):
    print("=== Lambda received event ===")
    print(event)
    return {
        'statusCode': 200,
        'body': 'Hello from Lambda!'
    }