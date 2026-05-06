//
//  TailorView.swift
//  Sider
//
//  Created by CoderWan on 2024/12/11.
//

import SwiftUI

struct TailorView: View {
    
    @Environment(\.colorScheme) private var scheme
    
    @State private var viewModel: TailorViewViewModel
    
    let image: UIImage
    
    let dismissBlock: () -> Void
    
    let croppedBlock: (UIImage) -> Void
    
    let closeBlock: () -> Void
    
    @State private var isAppear = false
    
    init(image: UIImage,
         dismissBlock: @escaping () -> Void,
         croppedBlock: @escaping (UIImage) -> Void,
         closeBlock: @escaping () -> Void) {
        self._viewModel = .init(wrappedValue: .init(image: image))
        self.image = image
        self.dismissBlock = dismissBlock
        self.croppedBlock = croppedBlock
        self.closeBlock = closeBlock
        
    }
    
    var body: some View {
        VStack(spacing: 0) {
            rotateBottom
                .padding(.top, SwiftApp.safeAreaInsets.top)
                .zIndex(1)
            VStack(spacing: 32) {
                photoPreview
                    .padding(.horizontal, 20)
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: .black.opacity(0), location: 0.00),
                        Gradient.Stop(color: .black.opacity(0.4), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
                .frame(height: 116)
                .overlay(alignment: .bottom) {
                    bottomOperationView
                        .padding(.horizontal, 40)
                        .padding(.bottom, SwiftApp.safeAreaInsets.bottom + 14)
                }
            }
            .zIndex(0)
        }
        .background(Color.black.ignoresSafeArea())
        .transition(.opacity)
        .clipped()
    }
    
    var rotateBottom: some View {
        HStack {
            Spacer()
            Button {
                withAnimation {
                    viewModel.adjustRotate -= 90
                }
                Task {
                    viewModel.adjustRotate = 0
                    viewModel.rotate()
                    viewModel.rotateCropRect()
                }
            } label: {
                Image(systemName: "rotate.right")
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .contentShape(Rectangle())
            }
        }
    }
    
    var bottomOperationView: some View {
        HStack {
            // 取消按钮
            operateButton(icon: "xmark", size: 18) {
                dismissBlock()
            }
            Spacer()
            // 确认按钮
            Button {
                closeBlock()
                viewModel.getNewestCroppedImage { cropped in
                    croppedBlock(cropped ?? image)
                }
            } label: {
                Circle()
                    .fill(DS.ColorToken.brandPrimary(scheme))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: DS.ColorToken.brandPrimary(scheme).opacity(0.4),
                            radius: 12, y: 4)
            }
            Spacer()
            // 重置按钮
            operateButton(icon: "arrow.counterclockwise", size: 16) {
                viewModel.reset()
            }
        }
    }

    func operateButton(icon: String,
                       size: CGFloat,
                       action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
    
    var photoPreview: some View {
        VStack {
            Spacer(minLength: 0)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .rotationEffect(Angle(degrees: Double(viewModel.rotateState.rawValue)))
                .scaleEffect(viewModel.imageScale)
                .offset(x: viewModel.currentOffset.x,
                        y: viewModel.currentOffset.y)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                withAnimation {
                    isAppear = true
                }
            }
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { newValue in
            viewModel.tailorSize = newValue
        })
        .rotationEffect(Angle(degrees: Double(viewModel.adjustRotate)))
        .overlay {
            if viewModel.tailorSize != .zero && isAppear {
                AdjustableMaskedView(
                    cropRect: $viewModel.cropRect,
                    maskedSize: viewModel.tailorSize
                ) {
                    viewModel.cropAreaMoveToCenter()
                }
                .rotationEffect(Angle(degrees: Double(viewModel.adjustRotate)))
            }
        }
        .safeAreaInset(edge: .bottom, content: {
            Spacer().frame(height: 50)
        })
        .gesture(
            SimultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        viewModel.freshScale(with: value.magnification)
                    }
                    .onEnded { value in
                        viewModel.adjustSizeAndPosition()
                    },
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        viewModel.freshOffset(with: value.translation)
                    }
                    .onEnded { value in
                        viewModel.limitPosition()
                        viewModel.cropImage()
                    }
            )
        )
        .task(id: viewModel.cropRect) {
            viewModel.adjustSizeAndPosition()
        }
    }
}
