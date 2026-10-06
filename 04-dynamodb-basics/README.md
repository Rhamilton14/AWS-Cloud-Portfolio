# DynamoDB Basics

### Objective
Create a NoSQL table and learn how DynamoDB stores and finds data.

### What I did
I created a DynamoDB table with a string partition key named `id`, added an item with string and number attributes, and looked it up by its key in the Console's table explorer.

### Services I learned
- **Amazon DynamoDB**: table creation, key schema design, and creating and browsing items

## Steps
1. Created table `dynamodb-basics` with partition key `id` (String), default settings.
2. Added an item with **Explore table items → Create item**:

| Attribute | Type   | Value           |
|-----------|--------|-----------------|
| id        | String | item-1          |
| name      | String | Cloud Colosseum |
| level     | Number | 1               |

3. Filtered by partition key `item-1` and confirmed all three attributes.

## Screenshots
<!-- ![Table active](screenshots/table-active.png) -->
<!-- ![Item details](screenshots/item.png) -->

## What I learned
- DynamoDB only needs the key schema up front; every other attribute is flexible per item.
- The partition key is how DynamoDB finds an item quickly, so choosing it well matters.
