SELECT reclada_object.create_subclass('{
    "class": "RecladaObject",
    "attributes": {
        "newClass": "revision",
        "properties": {
            "branch": {"type": "string"},
            "user": {"type": "string"},
            "num": {"type": "number"},
            "dateTime": {"type": "string"}
        },
        "required": ["dateTime"]
    }
}'::jsonb);

-- 7
SELECT reclada_object.create_subclass('{
    "class": "RecladaObject",
    "attributes": {
        "newClass": "Component",
        "properties": {
            "name": {"type": "string"},
            "commitHash": {"type": "string"},
            "repository": {"type": "string"}
        },
        "required": ["name","commitHash","repository"]
    }
}'::jsonb);

--{ 9 DTOJsonSchema
SELECT reclada_object.create_subclass('{
    "class": "RecladaObject",
    "attributes": {
        "newClass": "DTOJsonSchema",
        "properties": {
            "schema": {"type": "object"},
            "function": {"type": "string"}
        },
        "required": ["schema","function"]
    }
}'::jsonb);

     SELECT reclada_object.create('{
            "GUID":"db0ad26e-a522-4907-a41a-a82a916fdcf9",
            "class": "DTOJsonSchema",
            "attributes": {
                "function": "reclada_object.list",
                "schema": {
                    "type": "object",
                    "anyOf": [
                        {
                            "required": [
                                "transactionID"
                            ]
                        },
                        {
                            "required": [
                                "class"
                            ]
                        },
                        {
                            "required": [
                                "filter"
                            ]
                        }
                    ],
                    "properties": {
                        "class": {
                            "type": "string"
                        },
                        "limit": {
                            "anyOf": [
                                {
                                    "enum": [
                                        "ALL"
                                    ],
                                    "type": "string"
                                },
                                {
                                    "type": "integer"
                                }
                            ]
                        },
                        "filter": {
                            "type": "object"
                        },
                        "offset": {
                            "type": "integer"
                        },
                        "orderBy": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": [
                                    "field"
                                ],
                                "properties": {
                                    "field": {
                                        "type": "string"
                                    },
                                    "order": {
                                        "enum": [
                                            "ASC",
                                            "DESC"
                                        ],
                                        "type": "string"
                                    }
                                }
                            }
                        },
                        "transactionID": {
                            "type": "integer"
                        }
                    }
                }
            }
            
        }'::jsonb);
--} 9 DTOJsonSchema

--{ 11 User
SELECT reclada_object.create_subclass('{
    "GUID":"db0db7c0-9b25-4af0-8013-d2d98460cfff",
    "class": "RecladaObject",
    "attributes": {
        "newClass": "User",
        "properties": {
            "login": {"type": "string"}
        },
        "required": ["login"]
    }
}'::jsonb);

    select reclada_object.create('{
            "GUID": "db0789c1-1b4e-4815-b70c-4ef060e90884",
            "class": "User",
            "attributes": {
                "login": "dev"
            }
        }'::jsonb);
--} 11 User


-- 1
SELECT reclada_object.create_subclass('{
    "class": "RecladaObject",
    "attributes": {
        "newClass": "Cat",
        "properties": {
            "name": {"type": "string"},
            "weight": {"type": "number"},
            "color": {"type": "string"}
        },
        "required": ["name","weight","color"]
    }
}'::jsonb);


        SELECT reclada_object.create('{
            "GUID":"7ED4BD4B-C114-451B-9F13-AE2BF6FEB5B2",
            "class": "Cat",
            "attributes": {
                "name": "Richard",
                "weight": 99,
                "color": "green"
            }
        }'::jsonb);

        SELECT reclada_object.create('{
            "GUID":"C74E95F8-347C-4934-9E77-7E3CF6F9F4E3",
            "class": "Cat",
            "attributes": {
                "name": "Vovan",
                "weight": 78,
                "color": "green"
            }
        }'::jsonb);

        SELECT reclada_object.create('{
            "GUID":"DB6796DF-97D4-45AB-991B-10D1A610159B",
            "class": "Cat",
            "attributes": {
                "name": "Igor",
                "weight": 34,
                "color": "black"
            }
        }'::jsonb);

--} 1
