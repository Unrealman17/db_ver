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
                "weight": 81,
                "color": "green"
            }
        }'::jsonb);

        SELECT reclada_object.create('{
            "GUID":"5C3D698C-D78E-4096-B812-387FEF483FE2",
            "class": "Cat",
            "attributes": {
                "name": "Irina",
                "weight": 57,
                "color": "green"
            }
        }'::jsonb);
