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
