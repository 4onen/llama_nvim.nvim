#!/usr/bin/env python3
"""
This is a dummy server that simulates the behavior of just the /completion and
/health endpoints of the llama.cpp server. It is intended to be used to test
and develop the client without needing to have a running llama.cpp server
(which burns so much CPU time.)
"""

import asyncio
import aiohttp
import aiohttp.web
import re
import json

# This is a long string of lorem ipsum text that we will use to simulate the
# output of the model. Tokenization is done with a simple regex that splits
# on whitespace.
lorem_ipsum = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean congue mi sed varius tincidunt. Aenean sollicitudin urna eu massa blandit eleifend. Aenean vel libero ut est finibus facilisis at ut mi. Praesent ut tempus metus. Nam dapibus tortor id viverra dapibus. Aliquam et diam a libero posuere vehicula. Sed eu consequat metus.

Etiam lacinia, ex fermentum tristique tincidunt, est odio fermentum enim, nec aliquet justo nunc eu leo. In magna urna, convallis sit amet porttitor eu, lacinia vitae est. Nam a sollicitudin ipsum, a finibus augue. Donec ac fringilla tellus, ac posuere urna. Curabitur quam diam, congue non tempor id, tincidunt at ipsum. Quisque luctus lacus a maximus rutrum. Nunc blandit dignissim ipsum, ac maximus arcu efficitur sed. Vivamus pharetra tortor ut nunc tempus efficitur. Nunc id urna ligula. Vivamus a justo ac neque placerat volutpat.

Donec laoreet efficitur lorem ac dignissim. Integer vehicula venenatis mollis. Quisque vulputate sollicitudin iaculis. In consequat efficitur imperdiet. Aliquam aliquam quis turpis eu venenatis. Etiam iaculis nunc at est ultricies ornare. Sed at neque molestie, eleifend eros vitae, pretium ante. Vestibulum ipsum justo, gravida sed varius sed, elementum et lectus. Vivamus porta augue felis, vitae tempus eros euismod ac. Nullam blandit pharetra turpis aliquet hendrerit. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Vestibulum nec lacus sapien. Praesent nisi mauris, aliquam iaculis gravida quis, vestibulum non risus. Integer ornare ultrices ex at gravida. Cras ac scelerisque purus, et laoreet ligula. Duis consequat urna eget iaculis faucibus.

Donec non erat in nulla euismod lobortis. Nullam molestie, lacus quis pharetra sagittis, nisl eros accumsan lectus, sed aliquet turpis ipsum eu justo. Etiam ornare quam nec ullamcorper euismod. Fusce ipsum neque, pulvinar eget enim vel, maximus elementum lorem. Cras convallis mi sit amet mi tempus congue. Vestibulum a convallis risus. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Curabitur facilisis ligula quis dignissim imperdiet. Suspendisse tincidunt pulvinar pharetra. Nunc ultrices id enim aliquam dignissim. Phasellus porttitor fringilla magna, et pellentesque neque pretium sed. Nam convallis dolor sit amet est gravida, eu commodo quam maximus. Pellentesque at tellus erat. Suspendisse non nisi aliquet, tempus lorem ultricies, cursus massa. Quisque nunc ipsum, eleifend a pharetra quis, hendrerit vitae sem.

Fusce vitae dui eu dui malesuada finibus eu a nulla. Cras rutrum elementum interdum. Curabitur ultrices vehicula leo et sodales. Nulla consequat urna id orci rhoncus, in lacinia dui auctor. Mauris eget semper diam. Fusce et diam ut orci ullamcorper fermentum facilisis vel lectus. Donec dictum lacus sodales nulla tempor ultrices. Praesent scelerisque tellus sit amet orci efficitur, quis varius nunc imperdiet. Donec porttitor sollicitudin lectus, ac varius est elementum sit amet. Maecenas orci tortor, sodales eget molestie ac, auctor in nunc. Curabitur quis eros ut ligula ullamcorper mattis eget sed nulla. Morbi nulla justo, ultrices quis ipsum in, ullamcorper dignissim justo. Nullam ac dui pretium, tempus ante eget, rutrum turpis. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Nam nec tincidunt tortor. In quis odio quis ligula porttitor commodo id congue metus.
"""
tokenizer = re.compile(r"(?:^|\s+)[^\s]+", re.MULTILINE)
lorem_ipsum_tokens = tokenizer.findall(lorem_ipsum)

SIMULATED_TOK_INFERENCE_TIME = 0.1

# Respond in llama.cpp completion format
async def handle(request):
    # Check that the request has accept
    # headers for an SSE stream
    if 'text/event-stream' not in request.headers.get('Accept', ''):
        return aiohttp.web.Response(status=406, text="This server only supports text/event-stream accept headers")
    # Read the request as JSON
    data = await request.json()
    # Validate the request
    if not isinstance(data, dict):
        return aiohttp.web.Response(status=400, text="Request must be a JSON object")
    # Check that the request has the required keys
    if "prompt" not in data or "n_predict" not in data:
        return aiohttp.web.Response(status=400, text="Request must have 'prompt' and 'n_predict' keys")
    if "stream" not in data or data["stream"] != True:
        # This server doesn't implement non-streaming completions because
        # we want to test streaming clients.
        return aiohttp.web.Response(status=501, text="This server only supports streaming completions")

    try:
        to_predict = int(data["n_predict"])
    except ValueError:
        return aiohttp.web.Response(status=400, text="n_predict must be an integer")

    response = aiohttp.web.StreamResponse()
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Connection'] = 'keep-alive'
    await response.prepare(request)

    input_tokens = tokenizer.findall(str(data["prompt"]))
    input_token_count = len(input_tokens)

    # There's probably a more elegant way to format the packets but I'm lazy.
    packet = {"content": "TODO", "stop": False, "id_slot":0}
    # Send the completion one token at a time
    for _, token in zip(range(to_predict),lorem_ipsum_tokens):
        packet["content"] = token
        await response.write(data=f"data: {json.dumps(packet)}\n\n".encode("utf-8"))
        await asyncio.sleep(SIMULATED_TOK_INFERENCE_TIME)

    # Final packet has no content and stop=True
    packet["stop"] = True
    packet["content"] = ""
    # Fake a few other statistics -- might stick tok/s in the client later.
    packet["model"] = "TODO"
    packet["tokens_predicted"] = to_predict
    packet["tokens_evaluated"] = input_token_count
    await response.write(data=f"data: {json.dumps(packet)}\n\n".encode("utf-8"))

    await response.write_eof()
    return response

async def handle_health(_):
    response = {"status": "ok", "slots_idle": 1}
    return aiohttp.web.json_response(response)

if __name__ == "__main__":
    import sys
    # The dummy server accepts up to one argument: a float that sets the
    # simulated time to infer a token. This is useful for testing the client
    # with different speeds of server response.
    if len(sys.argv) > 1:
        try:
            SIMULATED_TOK_INFERENCE_TIME = float(sys.argv[1])
        except ValueError:
            print(f"Invalid latency value: {sys.argv[1]}", file=sys.stderr)
            sys.exit(1)
    app = aiohttp.web.Application()
    app.router.add_get('/health', handle_health)
    app.router.add_post('/completion', handle)
    aiohttp.web.run_app(app, port=8080)
