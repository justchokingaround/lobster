$url = "https://flixhq.to/search/fight-club"

$linksAndTitles = Invoke-WebRequest -Uri $url -UseBasicParsing | 
Select-Object -ExpandProperty Links | 
Where-Object -Property href -Match "/movie/" | 
Select-Object -Property href, title |
Sort-Object -Property href -Unique |
Format-Table -AutoSize |
Out-String -Stream |
ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_)
} | Select-Object -Skip 3

$movieId = $linksAndTitles | fzf --with-nth 2..
$movieId = $movieId -split "-" | Select-Object -Last 1 | Select-String -Pattern "\d+" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value

$moviePage = Invoke-WebRequest -Uri "https://flixhq.to/ajax/movie/episodes/$movieId" -UseBasicParsing |
Select-Object -ExpandProperty Links |
Where-Object -Property href -Match "/watch-movie/" |
Where-Object -Property title -Match "Vidcloud" |
Select-Object -Property href |
Out-String -Stream |
Select-Object -Skip 3

$pattern = "\d+$"
$episodeId = $moviePage | Select-String -Pattern $pattern | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value

$embedLink = Invoke-WebRequest -Uri "https://flixhq.to/ajax/sources/$episodeId" -UseBasicParsing | ConvertFrom-Json |
Select-Object -ExpandProperty link

$providerLink = $embedLink | Select-String -Pattern "https://\w+.\w+.\w+/" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value
$embedType = $embedLink -split "/embed-" | Select-Object -Last 1 | Select-String -Pattern "\d+" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value
$sourceId = $embedLink | Select-String -Pattern "(?<=4/|6/)(.*)(?=\?z=)" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value

# $keyHtml = Invoke-WebRequest -Uri "https://github.com/enimax-anime/key/blob/e$embedType/key.txt" -UseBasicParsing
# $keyContent = $keyHtml.Content
# $pattern = '(?<=<td id="LC1" class="blob-code blob-code-inner js-file-line">)[^<]+'
# $key = [regex]::Match($keyContent, $pattern).Value

# {"sources":"U2FsdGVkX1/S0ODeINwtkYOiyTWn9yYGgxFTQkyXtgXy+PNxSQAQ5CTSdofkqOclaF8mFJptwb/TKHv1XO0QfyqECjoFiSZNnIuR1YvJCC8DAVR7cSQ4yjpixFXPRQSAXYt+74wHXUCHvuUbj8sC6/Fodq42BwFFGPp8/IenBCfkK3Fr4zihT1QR0xY20+BmQ3QUO3+kfjGpXNYHls9zpMQODGFvErOKD8/t4ydieIllUFEI+movz60HEfTqFPN+z0MhpZCS/r7c80noIpqlW6IAGWWNccg7ABAMU2N/l5Fx7yQvaA9N4rD4tgzO9YvCJA9q/GZRB5WCECvbUdj7qNUhmjwNPhC8J9nbo82CPULI3r0TiBYOfr0bPxXeiOs13LY1to4XWvJS31E76cm2TJWuET5fAsr4+jl57kgM/mHmOfsw+4jg6ViM9jNain3s6HpyP1xNT9SVYYbLHcG24cckPUnSrAfa13lN0XYSqAWOeL9sB6UtETxV81A9BTk1NGcsVcjXLZvxLccH7sLcLVs77NA4SD+ReFeK+vdieeAB+kDFRyVWYNwIwkz3sJai","tracks":[{"file":"https://cc.2cdns.com/30/0d/300da5b98ce4991553bb752f97ffb156/300da5b98ce4991553bb752f97ffb156.vtt","label":"English","kind":"captions","default":true},{"file":"https://prev.2cdns.com/_m_preview/e8/e8c05b70294a004173d8514ed4f6cc6f/thumbnails/sprite.vtt","kind":"thumbnails"}],"server":18}

# from the json, extract the sources and tracks
$jsonData = Invoke-WebRequest -Uri "${providerLink}ajax/embed-$embedType/getSources?id=$sourceId" -UseBasicParsing -Headers @{ "X-Requested-With" = "XMLHttpRequest" } | ConvertFrom-Json
$encryptedVideoLink = $jsonData.sources

$keyHtml = Invoke-WebRequest -Uri "https://github.com/enimax-anime/key/blob/e$embedType/key.txt" -UseBasicParsing
$keyContent = $keyHtml.Content
$pattern = '(?<=<td id="LC1" class="blob-code blob-code-inner js-file-line">)[^<]+'
$key = [regex]::Match($keyContent, $pattern).Value

# Decrypt the video link

# $decryptedVideoLink = $encryptedVideoLink | base64 -d | openssl enc -aes-256-cbc -d -md md5 -k $key
# print out the hex of the encryptedVideoLink
$encryptedVideoLink
# $key

# printf "%s" "$encryptedVideoLink" | base64 -d | openssl enc -aes-256-cbc -d -md md5 -k Q4kcnxeaPnJutQDxa2s
# from base64 import b64decode
# from hashlib import md5

# from Cryptodome.Cipher import AES
# from Cryptodome.Util.Padding import unpad


# def generate_key_from_salt(salt: bytes, secret, *, output=48):

#     key = md5(secret + salt).digest()
#     current_key = key

#     while len(current_key) < output:
#         key = md5(key + secret + salt).digest()
#         current_key += key

#     return current_key[:output]


# def decipher_salted_aes(encoded_url: str, secret, *, aes_mode=AES.MODE_CBC):

#     raw_value = b64decode(encoded_url.encode("utf-8"))
#     assert raw_value.startswith(b"Salted__"), "Not a salt."
#     key = generate_key_from_salt(raw_value[8:16], secret)

#     return (
#         unpad(AES.new(key[:32], aes_mode, key[32:]).decrypt(raw_value[16:]), 16)
#         .decode("utf-8", "ignore")
#         .lstrip(" ")
#     )


# Use the extracted video link and modified JSON data as needed
# Write-Host "Encrypted: $encrypted"
# Write-Host "Video Link: $video_link"
