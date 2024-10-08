import { ScryptedDeviceBase } from '@scrypted/sdk'
import sdk from '@scrypted/sdk'

import { arch, platform } from 'os'
import path from 'path'
import { existsSync } from 'fs'
import { mkdir, readdir, rmdir, chmod } from 'fs/promises'
import AdmZip from 'adm-zip'

import fastfetch from './fastfetch.json'

DL_ARCH = () ->
    if platform() == 'darwin'
        'universal'
    else
        switch arch()
            when 'x64' then 'amd64'
            when 'arm64' then 'aarch64'
            else throw new Error "unsupported architecture #{arch()}"

DL_PLATFORM = () ->
    switch platform()
        when 'darwin' then 'macos'
        when 'linux' then 'linux'
        when 'win32' then 'windows'
        else throw new Error "unsupported platform #{platform()}"

VERSION = fastfetch.version

class FastfetchPlugin extends ScryptedDeviceBase
    constructor: (nativeId) ->
        super nativeId
        @exe = new Promise (resolve, reject) =>
            @doDownload(resolve).catch(reject)

    doDownload: (resolve) ->
        url = "https://github.com/fastfetch-cli/fastfetch/releases/download/#{VERSION}/fastfetch-#{DL_PLATFORM()}-#{DL_ARCH()}.zip"

        pluginVolume = process.env.SCRYPTED_PLUGIN_VOLUME
        installDir = path.join pluginVolume, "fastfetch-#{VERSION}-#{DL_PLATFORM()}-#{DL_ARCH()}"

        platform_specific_path = ->
            if DL_PLATFORM() == 'windows'
                path.join installDir, 'fastfetch.exe'
            else
                path.join installDir, "fastfetch-#{DL_PLATFORM()}-#{DL_ARCH()}", 'usr', 'bin', 'fastfetch'

        unless existsSync installDir
            console.log "Clearing old fastfetch installations"
            existing = await readdir pluginVolume
            existing.forEach (file) =>
                if file.startsWith 'fastfetch-'
                    try
                        await rmdir path.join(pluginVolume, file), { recursive: true }
                    catch e
                        console.error e

            await mkdir installDir, { recursive: true }

            console.log "Downloading fastfetch"
            console.log "Using url: #{url}"
            response = await fetch url
            unless response.ok
                throw new Error "failed to download fastfetch: #{response.statusText}"

            zip = await response.arrayBuffer()
            admZip = new AdmZip (Buffer.from zip)
            admZip.extractAllTo installDir, true

        exe = platform_specific_path()
        unless DL_PLATFORM() == 'windows'
            await chmod exe, 0o755

        console.log "fastfetch executable: #{exe}"
        resolve exe

    getSettings: ->
        [
            {
                key: 'fastfetch_executable'
                title: 'fastfetch Executable Path'
                description: 'Path to the downloaded fastfetch executable.'
                value: await @exe
                readonly: true
            }
        ]

    getTTYSettings: ->
        {
            paths: [
                path.dirname (await @exe)
            ]
        }

    getDevice: (nativeId) ->
        # Management ui v2's PtyComponent expects the plugin device to implement
        # DeviceProvider and return the StreamService device via getDevice
        this

    connectStream: (input, options) ->
        core = sdk.systemManager.getDeviceByName('@scrypted/core')
        termsvc = await core.getDevice('terminalservice')
        termsvc_direct = await sdk.connectRPCObject termsvc

        if DL_PLATFORM() == 'windows'
            exe = await @exe
            tokens = exe.split path.sep
            fixed_tokens = tokens.map (token) =>
                if token.includes ' '
                    "\"#{token}\""
                else
                    token
            exe = fixed_tokens.join path.sep
            await termsvc_direct.connectStream input,
                cmd: ['cmd.exe', '/c', "#{exe} && timeout /t -1 /nobreak >nul"]
        else
            await termsvc_direct.connectStream input,
                cmd: ['bash', '-c', "\"#{await @exe}\" && while true; do sleep 86400; done"]

export default FastfetchPlugin