//
//  Assets.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

class Assets {
    private static var _meshLibrary: MeshLibrary!
    public static var Meshes: MeshLibrary { return _meshLibrary }
    
    private static var _singleSMMeshLibrary: SingleSMMeshLibrary!
    public static var SingleSMMeshes: SingleSMMeshLibrary { return _singleSMMeshLibrary }
    
    private static var _textureLibrary: TextureLibrary!
    public static var Textures: TextureLibrary { return _textureLibrary }
    
    private static var _modelLibrary: ModelLibrary!
    public static var Models: ModelLibrary { return _modelLibrary }
    
    public static func Initialize() {
        self._meshLibrary = MeshLibrary()
        self._singleSMMeshLibrary = SingleSMMeshLibrary()
        self._textureLibrary = TextureLibrary()
        
        // The model library needs to be initialized AFTER the mesh library:
        self._modelLibrary = ModelLibrary()
    }
}
