# Auto-Monocle for Home Assistant

Automatically discover cameras from Home Assistant and expose them to Alexa via [Monocle Gateway](https://monoclecam.com).

## Features

- **Auto-Discovery**: Automatically finds all camera entities in HA
- **UniFi Protect Support**: Works with UniFi Protect cameras
- **Generic Camera Support**: Works with any camera integration
- **Uses Friendly Names**: Cameras appear in Alexa with their HA names
- **Periodic Refresh**: Automatically updates camera list

## Requirements

1. **Monocle Account**: Sign up at [monoclecam.com](https://monoclecam.com)
2. **Monocle Token**: Get your API token from the Monocle dashboard
3. **Alexa Skill**: Enable the "Monocle" skill in your Alexa app
4. **RTSP Streams**: Your cameras must have RTSP stream URLs available

## Setup

### 1. Get Monocle Token

1. Create account at [monoclecam.com](https://monoclecam.com)
2. Go to Dashboard → API → Generate Token
3. Copy the token

### 2. Configure Add-on

Add the token to the add-on configuration:

```yaml
monocle_token: "your-token-here"
auto_discover: true
refresh_interval: 300
```

### 3. Enable Alexa Skill

1. Open Alexa app
2. Go to Skills & Games
3. Search for "Monocle"
4. Enable skill and link account

### 4. Discover Devices

1. Say "Alexa, discover devices"
2. Your cameras should appear

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `monocle_token` | Your Monocle API token | required |
| `auto_discover` | Auto-discover cameras from HA | true |
| `refresh_interval` | Seconds between camera refresh | 300 |
| `camera_filters` | List of camera name filters | [] |

## Camera Filters

Filter cameras by name or entity_id:

```yaml
camera_filters:
  - "front"
  - "doorbell"
  - "unifi"
```

Only cameras matching these filters will be added.

## Network Requirements

Monocle Gateway requires:
- **Port 443**: For secure Alexa communication
- **Internet access**: To communicate with Monocle cloud

## Usage

Once configured, say:

- "Alexa, show me [camera name]"
- "Alexa, show front door camera"

## Troubleshooting

### Cameras not discovered

1. Check that cameras have RTSP stream URLs
2. View add-on logs for discovery output
3. Ensure `stream_source` attribute is set

### Alexa can't find cameras

1. Re-run "Alexa, discover devices"
2. Check Monocle dashboard for registered cameras
3. Verify port 443 is accessible

### Stream not loading

1. Check camera RTSP URL is accessible
2. Ensure H.264 video codec
3. Try adding `@noaudio` tag if audio issues

## Home Assistant Automations

Trigger camera view when doorbell rings:

```yaml
automation:
  - alias: "Show doorbell on Alexa"
    trigger:
      - platform: state
        entity_id: binary_sensor.doorbell
        to: "on"
    action:
      - service: notify.alexa_media
        data:
          target: media_player.echo_show_living_room
          message: "Someone is at the door"
          data:
            type: announce
```

## Support

- [GitHub Issues](https://github.com/apbb2/claude-code-ha-addons/issues)
- [Monocle Forums](https://forum.monoclecam.com)
