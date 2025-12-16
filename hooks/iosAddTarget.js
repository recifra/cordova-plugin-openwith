//
//  iosAddTarget.js
//  This hook runs for the iOS platform when the plugin or platform is added.
//
// Source: https://github.com/DavidStrausz/cordova-plugin-today-widget
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 DavidStrausz
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

const PLUGIN_ID = 'cordova-plugin-openwith-ci'
const BUNDLE_SUFFIX = '.shareextension'

const fs = require('fs')
const plist = require('plist')
const path = require('path')
let packageJson
let bundleIdentifier

function redError (message) {
  return new Error('"' + PLUGIN_ID + '" \x1b[1m\x1b[31m' + message + '\x1b[0m')
}

function replacePreferencesInFile (filePath, preferences, asEntitlements) {
  let content
  try {
    content = fs.readFileSync(filePath, 'utf8')
    if (asEntitlements) {
      const entitlements = plist.parse(content)
      entitlements['com.apple.security.application-groups'] = '__GROUP_IDENTIFIER__'
      content = plist.build(entitlements)
    }
  } catch (error) {
    if (!asEntitlements) {
      throw error
    }
    const entitlements = {
      'com.apple.security.application-groups': '__GROUP_IDENTIFIER__'
    }
    content = plist.build(entitlements)
  }
  for (let i = 0; i < preferences.length; i++) {
    const pref = preferences[i]
    const regexp = new RegExp(pref.key, 'g')
    content = content.replace(regexp, pref.value)
  }
  fs.writeFileSync(filePath, content)
}

// Determine the full path to the app's xcode project file.
function findXCodeproject (context, callback) {
  fs.readdir(iosFolder(context), function (err, data) {
    let projectFolder
    let projectName
    // Find the project folder by looking for *.xcodeproj
    if (data && data.length) {
      data.forEach(function (folder) {
        if (folder.match(/\.xcodeproj$/)) {
          projectFolder = path.join(iosFolder(context), folder)
          projectName = path.basename(folder, '.xcodeproj')
        }
      })
    }

    if (!projectFolder || !projectName) {
      throw redError(
        'Could not find an .xcodeproj folder in: ' + iosFolder(context)
      )
    }

    if (err) {
      throw redError(err)
    }

    callback(projectFolder, projectName)
  })
}

// Determine the full path to the ios platform
function iosFolder (context) {
  return context.opts.cordova.project
    ? context.opts.cordova.project.root
    : path.join(context.opts.projectRoot, 'platforms/ios/')
}

function getPreferenceValue (configXml, name) {
  const value = configXml.match(
    new RegExp('name="' + name + '" value="(.*?)"', 'i')
  )
  if (value && value[1]) {
    return value[1]
  } else {
    return null
  }
}

function getCordovaParameter (configXml, variableName) {
  let variable = packageJson.cordova.plugins[PLUGIN_ID][variableName]
  if (!variable) {
    variable = getPreferenceValue(configXml, variableName)
  }
  return variable
}

// Get the bundle id from config.xml
function getBundleId (context, configXml) {
  const elementTree = require('elementtree')
  const etree = elementTree.parse(configXml)
  return etree.getroot().get('id')
}

function parsePbxProject (context, pbxProjectPath) {
  const xcode = require('xcode')
  console.log(
    '    Parsing existing project at location: ' + pbxProjectPath + '...'
  )
  let pbxProject
  if (context.opts.cordova.project) {
    pbxProject = context.opts.cordova.project.parseProjectFile(
      context.opts.projectRoot
    ).xcode
  } else {
    pbxProject = xcode.project(pbxProjectPath)
    pbxProject.parseSync()
  }
  return pbxProject
}

function forEachShareExtensionFile (context, callback) {
  const shareExtensionFolder = path.join(iosFolder(context), 'ShareExtension')
  if (!fs.existsSync(shareExtensionFolder)) {
    console.error('!!  Shared extension files have not been copied yet!!')
    return
  }
  fs.readdirSync(shareExtensionFolder).forEach(function (name) {
    // Ignore junk files like .DS_Store
    if (!/^\..*/.test(name)) {
      callback({
        name,
        path: path.join(shareExtensionFolder, name),
        extension: path.extname(name)
      })
    }
  })
}

function projectPlistPath (context, projectName) {
  return path.join(
    iosFolder(context),
    projectName,
    projectName + '-Info.plist'
  )
}

function projectPlistJson (context, projectName) {
  const plist = require('plist')
  const path = projectPlistPath(context, projectName)
  return plist.parse(fs.readFileSync(path, 'utf8'))
}

function getPreferences (context, configXml, projectName) {
  const plist = projectPlistJson(context, projectName)
  let group = 'group.' + bundleIdentifier + BUNDLE_SUFFIX
  if (getCordovaParameter(configXml, 'IOS_GROUP_IDENTIFIER')) {
    group = getCordovaParameter(configXml, 'IOS_GROUP_IDENTIFIER')
  }
  const uti = getCordovaParameter(configXml, 'IOS_UNIFORM_TYPE_IDENTIFIER')
  const supportsAttachmentCount = uti.includes('text') ? '10' : '0'
  const supportsFileCount = uti.includes('text') ? '10' : '0'
  const supportsImageCount = uti.includes('image') ? '10' : '0'
  const supportsUrlCount = uti.includes('text') ? '10' : '0'
  const supportsText = uti.includes('text') ? 'true' : 'false'
  return [
    {
      key: '__DISPLAY_NAME__',
      value: projectName
    },
    {
      key: '__BUNDLE_IDENTIFIER__',
      value: bundleIdentifier + BUNDLE_SUFFIX
    },
    {
      key: '__GROUP_IDENTIFIER__',
      value: group
    },
    {
      key: '__BUNDLE_SHORT_VERSION_STRING__',
      value: plist.CFBundleShortVersionString
    },
    {
      key: '__BUNDLE_VERSION__',
      value: plist.CFBundleVersion
    },
    {
      key: '__URL_SCHEME__',
      value: getCordovaParameter(configXml, 'IOS_URL_SCHEME')
    },
    {
      key: '__SUPPORTS_ATTACHMENT_COUNT__',
      value: supportsAttachmentCount
    },
    {
      key: '__SUPPORTS_FILE_COUNT__',
      value: supportsFileCount
    },
    {
      key: '__SUPPORTS_IMAGE_COUNT__',
      value: supportsImageCount
    },
    {
      key: '__SUPPORTS_URL_COUNT__',
      value: supportsUrlCount
    },
    {
      key: '__SUPPORTS_TEXT__',
      value: supportsText
    }
  ]
}

// Return the list of files in the share extension project, organized by type
function getShareExtensionFiles (context) {
  const files = { source: [], plist: [], resource: [] }
  const FILE_TYPES = { '.h': 'source', '.m': 'source', '.plist': 'plist' }
  forEachShareExtensionFile(context, function (file) {
    const fileType = FILE_TYPES[file.extension] || 'resource'
    files[fileType].push(file)
  })
  return files
}

module.exports = function (context) {
  const Q = require('q')
  const deferral = Q.defer()

  packageJson = require(path.join(context.opts.projectRoot, 'package.json'))

  let configXml = fs.readFileSync(
    path.join(context.opts.projectRoot, 'config.xml'),
    'utf-8'
  )
  if (configXml) {
    configXml = configXml.substring(configXml.indexOf('<'))
  }

  bundleIdentifier = getBundleId(context, configXml)

  findXCodeproject(context, function (projectFolder, projectName) {
    const pbxProjectPath = path.join(projectFolder, 'project.pbxproj')
    const pbxProject = parsePbxProject(context, pbxProjectPath)

    const files = getShareExtensionFiles(context)
    // inject entitlements at a common place (allow merge with Apple sign in)
    const entitlementsName = projectName + '.entitlements'
    const baseEntitlementsPath = path.join(projectName, 'Resources', entitlementsName)
    const entitlementsFile = {
      name: entitlementsName,
      path: path.join(iosFolder(context), baseEntitlementsPath),
      extension: path.extname(entitlementsName)
    }
    const mkpath = require('mkpath')
    mkpath.sync(path.dirname(entitlementsFile.path))
    files.plist.push(entitlementsFile)

    const preferences = getPreferences(context, configXml, projectName)
    files.plist.concat(files.source).forEach(function (file) {
      replacePreferencesInFile(file.path, preferences, file.extension === entitlementsFile.extension)
    })

    // Find if the project already contains the target and group
    let target =
      pbxProject.pbxTargetByName('ShareExt') ||
      pbxProject.pbxTargetByName('"ShareExt"')
    if (target) {
      console.log('    ShareExt target already exists.')
    }

    if (!target) {
      // Add PBXNativeTarget to the project
      target = pbxProject.addTarget(
        'ShareExt',
        'app_extension',
        'ShareExtension'
      )

      // Add a new PBXSourcesBuildPhase for our ShareViewController
      // (we can't add it to the existing one because an extension is kind of an extra app)
      pbxProject.addBuildPhase(
        [],
        'PBXSourcesBuildPhase',
        'Sources',
        target.uuid
      )

      // Add a new PBXResourcesBuildPhase for the Resources used by the Share Extension
      // (MainInterface.storyboard)
      pbxProject.addBuildPhase(
        [],
        'PBXResourcesBuildPhase',
        'Resources',
        target.uuid
      )
    }

    // Create a separate PBXGroup for the shareExtensions files, name has to be unique and path must be in quotation marks
    let pbxGroupKey = pbxProject.findPBXGroupKey({ name: 'ShareExtension' })
    if (pbxGroupKey) {
      console.log('    ShareExtension group already exists.')
    }
    if (!pbxGroupKey) {
      pbxGroupKey = pbxProject.pbxCreateGroup(
        'ShareExtension',
        'ShareExtension'
      )

      // Add the PbxGroup to cordovas "CustomTemplate"-group
      const customTemplateKey = pbxProject.findPBXGroupKey({
        name: 'CustomTemplate'
      })
      pbxProject.addToPbxGroup(pbxGroupKey, customTemplateKey)
    }

    // Add files which are not part of any build phase (config)
    files.plist.forEach(function (file) {
      pbxProject.addFile(file.name, pbxGroupKey)
    })

    // Add source files to our PbxGroup and our newly created PBXSourcesBuildPhase
    files.source.forEach(function (file) {
      pbxProject.addSourceFile(file.name, { target: target.uuid }, pbxGroupKey)
    })

    //  Add the resource file and include it into the targest PbxResourcesBuildPhase and PbxGroup
    files.resource.forEach(function (file) {
      pbxProject.addResourceFile(
        file.name,
        { target: target.uuid },
        pbxGroupKey
      )
    })

    const configurations = pbxProject.pbxXCBuildConfigurationSection()
    for (const key in configurations) {
      if (typeof configurations[key].buildSettings !== 'undefined') {
        const buildSettingsObj = configurations[key].buildSettings
        if (typeof buildSettingsObj.PRODUCT_NAME !== 'undefined') {
          buildSettingsObj.CODE_SIGN_ENTITLEMENTS = `"${baseEntitlementsPath}"`
          const productName = buildSettingsObj.PRODUCT_NAME
          if (productName.indexOf('ShareExt') >= 0) {
            buildSettingsObj.PRODUCT_BUNDLE_IDENTIFIER =
              bundleIdentifier + BUNDLE_SUFFIX
          }
        }
      }
    }

    // Add development team and provisioning profile
    const PROVISIONING_PROFILE = getCordovaParameter(
      configXml,
      'SHAREEXT_PROVISIONING_PROFILE'
    )
    const DEVELOPMENT_TEAM = getCordovaParameter(
      configXml,
      'SHAREEXT_DEVELOPMENT_TEAM'
    )
    if (PROVISIONING_PROFILE && DEVELOPMENT_TEAM) {
      console.log(
        'Adding team',
        DEVELOPMENT_TEAM,
        'and provisoning profile',
        PROVISIONING_PROFILE
      )
      const configurations = pbxProject.pbxXCBuildConfigurationSection()
      for (const key in configurations) {
        if (typeof configurations[key].buildSettings !== 'undefined') {
          const buildSettingsObj = configurations[key].buildSettings
          if (typeof buildSettingsObj.PRODUCT_NAME !== 'undefined') {
            const productName = buildSettingsObj.PRODUCT_NAME
            if (productName.indexOf('ShareExt') >= 0) {
              buildSettingsObj.PROVISIONING_PROFILE = PROVISIONING_PROFILE
              buildSettingsObj.DEVELOPMENT_TEAM = DEVELOPMENT_TEAM
              buildSettingsObj.CODE_SIGN_IDENTITY = '"Apple Development"'
              console.log('Added signing identities for extension!')
            }
          }
        }
      }
    }

    // Write the modified project back to disc
    // console.log('    Writing the modified project back to disk...');
    fs.writeFileSync(pbxProjectPath, pbxProject.writeSync())
    deferral.resolve()
  })

  return deferral.promise
}
